import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'arena.dart';
import 'danmaku_game.dart';

enum PickupType { power, bomb, oneUp, weaponVulcan, weaponLaser, weaponMissile }

/// Cápsula colecionável.
///
/// São poucas em tela ao mesmo tempo, então aqui `PositionComponent` é a
/// escolha certa — o oposto das balas. Cai devagar e, quando a nave chega
/// perto, é sugada até ela: essa "sucção" é o micro-prazer que faz o jogador
/// querer mergulhar para pegar.
class PowerUp extends PositionComponent with HasGameReference<DanmakuGame> {
  PowerUp({required this.type, required Vector2 at})
      : super(position: at.clone(), priority: 7);

  final PickupType type;
  double _t = 0;
  double _vy = -70; // sobe um tico ao nascer, depois cai (pequeno "pop")

  Color get _color => switch (type) {
        PickupType.power => const Color(0xFFFF8A3D),
        PickupType.bomb => const Color(0xFF35E1F5),
        PickupType.oneUp => const Color(0xFF4BF07A),
        PickupType.weaponVulcan => const Color(0xFFFF3B5C),
        PickupType.weaponLaser => const Color(0xFF4C6BFF),
        PickupType.weaponMissile => const Color(0xFFFF4FD8),
      };

  String get _glyph => switch (type) {
        PickupType.power => 'P',
        PickupType.bomb => 'B',
        PickupType.oneUp => '1UP',
        PickupType.weaponVulcan => 'V',
        PickupType.weaponLaser => 'L',
        PickupType.weaponMissile => 'M',
      };

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;

    final player = game.player;
    final dx = player.position.x - position.x;
    final dy = player.position.y - position.y;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist < kPickupCollectRadius) {
      game.collectPickup(type, position.clone());
      removeFromParent();
      return;
    }

    if (dist < kPickupMagnetRadius) {
      // Sucção: acelera em direção à nave, mais forte quanto mais perto.
      final pull = 260 + (1 - dist / kPickupMagnetRadius) * 620;
      position.x += (dx / dist) * pull * dt;
      position.y += (dy / dist) * pull * dt;
    } else {
      _vy = math.min(kPickupDriftSpeed, _vy + 320 * dt);
      position.y += _vy * dt;
      position.x += math.sin(_t * 2.2) * 26 * dt;
    }

    if (position.y > kArenaHeight + 40) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final pulse = 0.5 + 0.5 * math.sin(_t * 7);
    final r = type == PickupType.oneUp ? 20.0 : 16.0;

    canvas.drawCircle(
      Offset.zero,
      r * 1.5,
      Paint()
        ..color = _color.withValues(alpha: 0.25 + 0.25 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2),
      Radius.circular(r * 0.5),
    );
    canvas.drawRRect(rrect, Paint()..color = _color);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: _glyph,
        style: TextStyle(
          fontSize: type == PickupType.oneUp ? 12 : 20,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF05030F),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  }
}

/// Gema de pontos que cai dos inimigos destruídos.
///
/// O valor é multiplicado pela cadeia NO MOMENTO DA COLETA, não do drop — é
/// isso que cria o dilema gostoso: pegar já, ou segurar a cadeia alta e
/// coletar tudo valendo ×4?
class Gem extends PositionComponent with HasGameReference<DanmakuGame> {
  Gem({required Vector2 at, this.value = 40})
      : super(position: at.clone(), priority: 6) {
    final rng = math.Random();
    _vx = (rng.nextDouble() - 0.5) * 240;
    _vy = -120 - rng.nextDouble() * 140;
    _phase = rng.nextDouble() * math.pi * 2;
  }

  final int value;
  late double _vx;
  late double _vy;
  late final double _phase;
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;

    final player = game.player;
    final dx = player.position.x - position.x;
    final dy = player.position.y - position.y;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist < kPickupCollectRadius) {
      game.collectGem(value, position.clone());
      removeFromParent();
      return;
    }

    // Ímã maior que o das cápsulas: gema é chuva, não deve exigir pontaria.
    if (dist < kPickupMagnetRadius * 1.35) {
      final pull = 340 + (1 - dist / (kPickupMagnetRadius * 1.35)) * 900;
      position.x += (dx / dist) * pull * dt;
      position.y += (dy / dist) * pull * dt;
      return;
    }

    // Espalha no estouro e assenta numa queda lenta.
    _vx *= 1 - 2.8 * dt;
    _vy = math.min(kPickupDriftSpeed * 1.25, _vy + 420 * dt);
    position.x += _vx * dt;
    position.y += _vy * dt;

    if (position.y > kArenaHeight + 30) {
      // Deixou a medalha cair: a cadeia de valor reseta.
      game.onGemMissed();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final spin = _t * 4 + _phase;
    // "Giro" 3D barato: a largura oscila com o seno.
    final w = 7.0 * (0.35 + 0.65 * math.sin(spin).abs());
    const h = 9.0;

    final d = Path()
      ..moveTo(0, -h)
      ..lineTo(w, 0)
      ..lineTo(0, h)
      ..lineTo(-w, 0)
      ..close();
    canvas.drawPath(
      d,
      Paint()
        ..color = const Color(0xFFFFD23F)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawPath(
      d,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }
}
