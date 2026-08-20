import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/game/arena.dart';
import 'package:bullet_veil/game/danmaku_game.dart';
import 'package:bullet_veil/game/pickups.dart';

void main() {
  DanmakuGame build() => DanmakuGame(onGameOver: (score, graze, wave) {});

  Vector2 at() => Vector2(360, 800);

  group('progressão de arma', () {
    testWithGame<DanmakuGame>('começa no nível 1', build, (game) async {
      expect(game.weaponLevel, 1);
      expect(game.weaponLevelNotifier.value, 1);
    });

    testWithGame<DanmakuGame>(
      'duas cápsulas sobem do nível 1 para o 2',
      build,
      (game) async {
        game.collectPickup(PickupType.power, at());
        expect(game.weaponLevel, 1, reason: '1 cápsula ainda não sobe (custo 2)');
        game.collectPickup(PickupType.power, at());
        expect(game.weaponLevel, 2);
      },
    );

    testWithGame<DanmakuGame>(
      'coletar muitas cápsulas chega ao máximo e não passa',
      build,
      (game) async {
        for (var i = 0; i < 60; i++) {
          game.collectPickup(PickupType.power, at());
        }
        expect(game.weaponLevel, kMaxWeaponLevel);
      },
    );

    testWithGame<DanmakuGame>(
      'no máximo, cápsula extra vira pontos',
      build,
      (game) async {
        for (var i = 0; i < 60; i++) {
          game.collectPickup(PickupType.power, at());
        }
        expect(game.weaponLevel, kMaxWeaponLevel);
        final before = game.scoreNotifier.value;
        game.collectPickup(PickupType.power, at());
        expect(game.scoreNotifier.value, greaterThan(before));
      },
    );
  });

  group('naves e bombas', () {
    testWithGame<DanmakuGame>('começa com as naves iniciais', build,
        (game) async {
      expect(game.livesNotifier.value, kStartLives);
    });

    testWithGame<DanmakuGame>('1UP dá uma nave, respeitando o teto', build,
        (game) async {
      // Perde para abrir espaço e testar o ganho.
      game.livesNotifier.value = 1;
      game.collectPickup(PickupType.oneUp, at());
      expect(game.livesNotifier.value, 2);

      game.livesNotifier.value = kMaxLives;
      game.collectPickup(PickupType.oneUp, at());
      expect(game.livesNotifier.value, kMaxLives, reason: 'não passa do teto');
    });

    testWithGame<DanmakuGame>('cápsula de bomba soma, com teto', build,
        (game) async {
      final start = game.bombsNotifier.value;
      game.collectPickup(PickupType.bomb, at());
      expect(game.bombsNotifier.value, start + 1);

      game.bombsNotifier.value = kMaxBombs;
      game.collectPickup(PickupType.bomb, at());
      expect(game.bombsNotifier.value, kMaxBombs);
    });
  });

  group('dificuldade', () {
    testWithGame<DanmakuGame>(
      'começa devagar e acelera com as ondas',
      build,
      (game) async {
        game.update(0);
        final early = game.fireContext.speedScale;
        expect(early, lessThan(0.8), reason: 'abertura deve ser lenta');

        game.waveNotifier.value = 20;
        // waveNotifier é só o espelho; a rampa lê o contador interno via update.
        // Força várias ondas para o contador subir de verdade.
        for (var i = 0; i < 400 && game.fireContext.speedScale < 0.99; i++) {
          game.update(0.5);
        }
        expect(game.fireContext.speedScale, greaterThan(early));
        expect(game.fireContext.speedScale, lessThanOrEqualTo(1.0));
      },
    );
  });
}
