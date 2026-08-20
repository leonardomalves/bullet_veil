import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/game/arena.dart';
import 'package:bullet_veil/game/brain.dart';

/// O cérebro de ameaça: leitura de velocidade, interceptação e hábito.
void main() {
  ThreatBrain brain() => ThreatBrain(math.Random(7));

  test('aprende a velocidade do jogador (EMA converge)', () {
    final b = brain();
    // Jogador correndo para a direita a 300 px/s.
    for (var i = 0; i < 60; i++) {
      b.observe(1 / 60, Vector2(100 + i * 5, 900));
    }
    expect(b.velocity.x, closeTo(300, 45));
    expect(b.velocity.y, closeTo(0, 10));
  });

  test('fúria zero = mira ingênua; fúria alta = intercepta à frente', () {
    final b = brain();
    for (var i = 0; i < 60; i++) {
      b.observe(1 / 60, Vector2(200 + i * 5, 900));
    }
    final pos = Vector2(200 + 59 * 5, 900);
    final origin = Vector2(360, 100);

    b.aggression = 0;
    expect(b.intercept(origin, 300).x, closeTo(pos.x, 1),
        reason: 'sem fúria, atira onde o jogador ESTÁ');

    b.aggression = 1;
    expect(b.intercept(origin, 300).x, greaterThan(pos.x + 60),
        reason: 'com fúria, atira onde o jogador VAI ESTAR');
  });

  test('a previsão respeita os limites da arena', () {
    final b = brain()..aggression = 1;
    for (var i = 0; i < 60; i++) {
      b.observe(1 / 60, Vector2(kArenaWidth - 30 + i * 0.1, 900));
    }
    final p = b.intercept(Vector2(360, 100), 200);
    expect(p.x, lessThanOrEqualTo(kPlayerMaxX));
  });

  test('descobre o canto favorito (hábito com esquecimento)', () {
    final b = brain();
    // 10s vivendo na esquerda…
    for (var i = 0; i < 600; i++) {
      b.observe(1 / 60, Vector2(90, 900));
    }
    expect(b.favoriteX, lessThan(kArenaWidth / 3));
    // …depois 30s na direita: o hábito novo vence o velho.
    for (var i = 0; i < 1800; i++) {
      b.observe(1 / 60, Vector2(640, 900));
    }
    expect(b.favoriteX, greaterThan(kArenaWidth * 2 / 3));
  });

  test('chefe nunca mira como recruta: piso sobe por fase até o teto', () {
    expect(bossAggressionFloor(0), closeTo(0.55, 0.001));
    expect(bossAggressionFloor(1), closeTo(0.70, 0.001));
    expect(bossAggressionFloor(2), closeTo(0.85, 0.001));
    expect(bossAggressionFloor(9), closeTo(0.85, 0.001),
        reason: '85% é o teto do sistema — sempre há counter-play');
  });

  test('emboscada só acontece com fúria alta', () {
    final b = brain()..aggression = 0.2;
    var any = false;
    for (var i = 0; i < 200; i++) {
      any = any || b.rollAmbush();
    }
    expect(any, isFalse, reason: 'fúria baixa nunca embosca');

    b.aggression = 0.9;
    var hits = 0;
    for (var i = 0; i < 400; i++) {
      if (b.rollAmbush()) hits++;
    }
    expect(hits, greaterThan(60), reason: '~30% das miras viram emboscada');
    expect(hits, lessThan(200), reason: 'mas nunca a maioria — tem que ter mistura');
  });
}
