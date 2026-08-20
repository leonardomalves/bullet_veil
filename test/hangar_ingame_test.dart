import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/core/garage.dart';
import 'package:bullet_veil/game/arena.dart';
import 'package:bullet_veil/game/atlas.dart';
import 'package:bullet_veil/game/danmaku_game.dart';
import 'package:bullet_veil/game/difficulty.dart';
import 'package:bullet_veil/game/enemy.dart';

void main() {
  DanmakuGame withModules(Set<ShipModule> mods) => DanmakuGame(
        onGameOver: (score, graze, wave) {},
        modules: mods,
      );

  group('loadout chega na nave', () {
    testWithGame<DanmakuGame>(
      'asas e overdrive configuram o player',
      () => withModules({ShipModule.wingmen, ShipModule.overdrive}),
      (game) async {
        expect(game.player.wingmen, isTrue);
        expect(game.player.fireRateMul, lessThan(1.0));
        expect(game.hasWingmen, isTrue);
        expect(game.hasOverdrive, isTrue);
      },
    );

    testWithGame<DanmakuGame>(
      'sem módulos, a nave fica no padrão',
      () => withModules(const {}),
      (game) async {
        expect(game.player.wingmen, isFalse);
        expect(game.player.fireRateMul, 1.0);
      },
    );
  });

  group('escudo', () {
    testWithGame<DanmakuGame>(
      'absorve o primeiro dano sem perder nave',
      () => withModules({ShipModule.shield}),
      (game) async {
        expect(game.shieldNotifier.value, isTrue);
        final lives = game.livesNotifier.value;

        // Bala inimiga em cima da nave.
        game.enemyBullets.spawn(
          x: game.player.position.x,
          y: game.player.position.y,
          vx: 0,
          vy: 0,
          shape: BulletShape.orb,
          color: 0,
        );
        game.update(1 / 60);

        expect(game.livesNotifier.value, lives, reason: 'escudo segura o dano');
        expect(game.shieldNotifier.value, isFalse, reason: 'escudo consumido');
      },
    );

    testWithGame<DanmakuGame>(
      'sem escudo, o dano tira uma nave',
      () => withModules(const {}),
      (game) async {
        final lives = game.livesNotifier.value;
        game.enemyBullets.spawn(
          x: game.player.position.x,
          y: game.player.position.y,
          vx: 0,
          vy: 0,
          shape: BulletShape.orb,
          color: 0,
        );
        game.update(1 / 60);
        expect(game.livesNotifier.value, lives - 1);
      },
    );
  });

  group('chefes têm 3 tipos distintos por estágio', () {
    test('o tipo cicla dreadnought → mantis → núcleo', () {
      final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
      expect(kit.boss(1).bossType, BossType.dreadnought);
      expect(kit.boss(2).bossType, BossType.mantis);
      expect(kit.boss(3).bossType, BossType.core);
      expect(kit.boss(4).bossType, BossType.dreadnought, reason: 'volta a ciclar');
      // Silhuetas diferentes: raios distintos.
      expect(kit.boss(1).radius, isNot(kit.boss(2).radius));
    });
  });

  // Garante que os limites de movimento ainda fazem sentido (evita regressão
  // besta de constante trocada).
  test('constantes de arena coerentes', () {
    expect(kPlayerMaxX, greaterThan(kPlayerMinX));
    expect(kPlayerMaxY, greaterThan(kPlayerMinY));
    expect(kStartLives, greaterThan(0));
  });
}
