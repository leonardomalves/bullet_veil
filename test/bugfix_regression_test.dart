import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/game/atlas.dart';
import 'package:bullet_veil/game/danmaku_game.dart';
import 'package:bullet_veil/game/pickups.dart';

/// Regressões dos bugs achados no design review.
void main() {
  DanmakuGame build() => DanmakuGame(onGameOver: (s, g, w) {});

  testWithGame<DanmakuGame>(
    'subir de arma NÃO teleporta a nave (o cascade mutava player.position)',
    build,
    (game) async {
      final before = game.player.position.clone();
      // Duas cápsulas P no nível 1 = 0.5 + 0.5 → sobe para Lv.2 (_onWeaponUp).
      game.collectPickup(PickupType.power, Vector2(100, 100));
      game.collectPickup(PickupType.power, Vector2(100, 100));
      expect(game.weaponLevel, 2, reason: 'sanidade: o upgrade aconteceu');
      expect(game.player.position, before,
          reason: 'a nave tem que ficar onde estava');
    },
  );

  testWithGame<DanmakuGame>(
    'deixar medalha cair zera o chip do HUD (não mostra o degrau seguinte)',
    build,
    (game) async {
      game.collectGem(0, Vector2(360, 400));
      expect(game.medalNotifier.value, greaterThan(0));
      game.onGemMissed();
      expect(game.medalNotifier.value, 0);
    },
  );

  testWithGame<DanmakuGame>(
    'tomar dano zera o chip de medalhas junto com a corrente',
    build,
    (game) async {
      game.collectGem(0, Vector2(360, 400));
      game.enemyBullets.spawn(
        x: game.player.position.x,
        y: game.player.position.y,
        vx: 0,
        vy: 0,
        shape: BulletShape.orb,
        color: 0,
      );
      game.update(1 / 60);
      expect(game.medalNotifier.value, 0);
    },
  );
}
