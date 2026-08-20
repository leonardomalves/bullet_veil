import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/core/replay.dart';
import 'package:bullet_veil/game/danmaku_game.dart';

/// Formato de replay v1: a régua fixa, a integridade e a gravação em jogo.
void main() {
  ReplayRecorder rec() =>
      ReplayRecorder(seed: 20260731, mode: 'daily', clientVersion: 'test');

  test('reamostra frames irregulares numa régua fixa de 20 Hz', () {
    final r = rec();
    // 1 segundo de jogo em frames tortos: 20 amostras, sempre.
    for (final dt in [0.016, 0.033, 0.008, 0.143, 0.3, 0.5]) {
      r.sample(dt, 360.5, 1020.4);
    }
    expect(r.sampleCount, 20);
  });

  test('eventos ancoram no índice da amostra e o payload fecha', () {
    final r = rec();
    r.sample(0.5, 100, 200); // 10 amostras
    r.event('bomb');
    r.sample(0.5, 100, 200); // +10
    r.finish(score: 5000, wave: 7);
    r.sample(1, 0, 0); // pós-finish: ignorado
    r.event('bomb');

    final p = r.payload;
    expect(p['v'], 1);
    expect(p['seed'], 20260731);
    expect((p['x'] as List).length, 20);
    expect(p['ev'], [
      {'t': 10, 'e': 'bomb'}
    ]);
    expect(p['score'], 5000);
    expect(p['dur'], 1.0);
  });

  test('encode/decode dá a volta e o sha muda com o conteúdo', () {
    final a = rec()
      ..sample(0.25, 10, 20)
      ..finish(score: 1, wave: 1);
    final b = rec()
      ..sample(0.25, 10, 20)
      ..finish(score: 2, wave: 1);

    final decoded = ReplayRecorder.decode(a.encode());
    expect(decoded['seed'], 20260731);
    expect((decoded['x'] as List).length, a.sampleCount);
    expect(a.sha256Hex, isNot(b.sha256Hex),
        reason: 'score diferente → hash diferente');
  });

  testWithGame<DanmakuGame>(
    'partida diária grava trajetória; comum não grava nada',
    () => DanmakuGame(onGameOver: (s, g, w) {}, daily: true, seed: 20260731),
    (game) async {
      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
      }
      expect(game.recorder, isNotNull);
      expect(game.recorder!.sampleCount, closeTo(20, 2),
          reason: '1s de jogo ≈ 20 amostras');

      game.useBomb();
      expect(
        game.recorder!.payload['ev'],
        anyElement(predicate<Map>((e) => e['e'] == 'bomb')),
      );
    },
  );

  testWithGame<DanmakuGame>(
    'partida comum segue sem gravador (custo zero fora do diário)',
    () => DanmakuGame(onGameOver: (s, g, w) {}),
    (game) async {
      game.update(1 / 60);
      expect(game.recorder, isNull);
    },
  );
}
