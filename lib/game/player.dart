import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../core/garage.dart';
import '../core/sfx.dart';
import 'arena.dart';
import 'atlas.dart';
import 'bullet_field.dart';
import 'danmaku_game.dart';
import 'sprites.dart';

/// As três armas especiais, estilo Raiden. Cada uma tem um contrato claro:
/// Vulcan cobre área, Laser fura fila (perfurante, dano alto num corredor),
/// Míssil persegue (menos dano, zero pontaria). Trocar é tática, não upgrade.
enum WeaponType { vulcan, laser, missile }

extension WeaponTypeUi on WeaponType {
  String get label => switch (this) {
        WeaponType.vulcan => 'VULCAN',
        WeaponType.laser => 'LASER',
        WeaponType.missile => 'MÍSSEIS',
      };

  Color get color => switch (this) {
        WeaponType.vulcan => const Color(0xFFFF3B5C),
        WeaponType.laser => const Color(0xFF4C6BFF),
        WeaponType.missile => const Color(0xFFFF4FD8),
      };
}

class Player extends PositionComponent with HasGameReference<DanmakuGame> {
  Player({
    this.skin = ShipSkin.aurora,
    this.wingmen = false,
    this.fireRateMul = 1.0,
    this.wingmenDamage = 0.8,
  }) : super(
          position: Vector2(kArenaWidth / 2, kArenaHeight - 260),
          priority: 8,
        );

  static const double bulletSpeed = 940;

  /// Loadout do hangar.
  final ShipSkin skin;
  final bool wingmen;
  final double fireRateMul;

  /// Dano por tiro dos drones (sobe com o nível do módulo ALAS).
  final double wingmenDamage;

  static const _optionOffsets = [
    Offset(-38, 22),
    Offset(38, 22),
    Offset(-66, 44),
    Offset(66, 44),
  ];
  final List<Vector2> _optionPos = List.generate(4, (_) => Vector2.zero());

  // Drones auxiliares (módulo ALAS): ficam mais afastados e sempre ativos.
  static const _wingOffsets = [Offset(-58, 30), Offset(58, 30)];
  final List<Vector2> _wingPos = List.generate(2, (_) => Vector2.zero());

  double invuln = 0;
  double _fireCd = 0;
  double _trailCd = 0;
  double _t = 0;
  bool _optionsPlaced = false;

  /// Cor do rastro no atlas de balas, casada com a skin.
  int get _trailColor => switch (skin) {
        ShipSkin.aurora => 3, // ciano
        ShipSkin.crimson => 0, // vermelho
        ShipSkin.gold => 5, // ouro
        ShipSkin.voidfire => 1, // magenta
        ShipSkin.spectre => 6, // branco
      };

  bool get vulnerable => invuln <= 0;

  int get _optionCount {
    final l = game.weaponLevel;
    if (l >= 6) return 4;
    if (l >= 5) return 2;
    return 0;
  }

  void moveBy(Vector2 delta) {
    position.x = (position.x + delta.x).clamp(kPlayerMinX, kPlayerMaxX);
    position.y = (position.y + delta.y).clamp(kPlayerMinY, kPlayerMaxY);
  }

  void onHit() => invuln = kInvulnDuration;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (invuln > 0) invuln -= dt;

    for (var i = 0; i < 4; i++) {
      final target = Vector2(
        position.x + _optionOffsets[i].dx,
        position.y + _optionOffsets[i].dy,
      );
      if (!_optionsPlaced) {
        _optionPos[i].setFrom(target);
      } else {
        _optionPos[i].lerp(target, (14 * dt).clamp(0.0, 1.0));
      }
    }
    if (wingmen) {
      for (var i = 0; i < 2; i++) {
        final target = Vector2(
          position.x + _wingOffsets[i].dx,
          position.y + _wingOffsets[i].dy,
        );
        _optionsPlaced
            ? _wingPos[i].lerp(target, (10 * dt).clamp(0.0, 1.0))
            : _wingPos[i].setFrom(target);
      }
    }
    _optionsPlaced = true;

    _fireCd -= dt;
    if (_fireCd <= 0) {
      _fireCd = _fireRate;
      _fireWeapon(game.playerBullets);
      sfx.shot(); // throttled internamente — tapete, não solo
    }

    // Rastro do motor: velocidade percebida quase de graça (mesmo atlas).
    _trailCd -= dt;
    if (_trailCd <= 0) {
      _trailCd = 0.035;
      game.sparks.burst(
        x: position.x,
        y: position.y + 28,
        color: _trailColor,
        count: 1,
        speed: 40,
        scale: 0.45,
        life: 0.3,
      );
    }
  }

  double get _fireRate {
    final lvl = game.weaponLevel;
    final base = switch (game.weaponType) {
      // Vulcan metralha; laser tem cadência mais pesada; míssil é o mais lento.
      WeaponType.vulcan => (0.078 - lvl * 0.004).clamp(0.045, 0.078),
      WeaponType.laser => (0.115 - lvl * 0.005).clamp(0.082, 0.115),
      WeaponType.missile => (0.16 - lvl * 0.006).clamp(0.115, 0.16),
    };
    return base * fireRateMul; // OVERDRIVE encurta o intervalo
  }

  void _fireWeapon(BulletField f) {
    switch (game.weaponType) {
      case WeaponType.vulcan:
        _fireVulcan(f);
      case WeaponType.laser:
        _fireLaser(f);
      case WeaponType.missile:
        _fireMissile(f);
    }
    _fireOptions(f);
  }

  // ── Vulcan: leque que alarga com o nível ─────────────────────────────────

  void _fireVulcan(BulletField f) {
    final lvl = game.weaponLevel;
    final x = position.x;
    final y = position.y - 24;
    final col = lvl >= 6
        ? 1
        : lvl >= 4
            ? 7
            : 3;
    const b = bulletSpeed;

    void shot(double ox, double oy, double vx, double vy, {double sc = 0.72}) {
      f.spawn(
        x: x + ox,
        y: y + oy,
        vx: vx,
        vy: vy,
        shape: BulletShape.laser,
        color: col,
        scale: sc,
      );
    }

    void spread(int n, double arc, {double sc = 0.72}) {
      for (var i = 0; i < n; i++) {
        final t = n == 1 ? 0.0 : (i / (n - 1)) - 0.5;
        final a = -math.pi / 2 + t * arc;
        shot(t * 20, 0, math.cos(a) * b, math.sin(a) * b, sc: sc);
      }
    }

    switch (lvl) {
      case 1:
        shot(0, 0, 0, -b, sc: 0.6);
      case 2:
        shot(-9, 0, 0, -b);
        shot(9, 0, 0, -b);
      case 3:
        shot(0, -6, 0, -b);
        shot(-13, 0, -70, -b);
        shot(13, 0, 70, -b);
      case 4:
        shot(-8, -4, 0, -b);
        shot(8, -4, 0, -b);
        spread(3, 0.5);
      case 5:
        spread(5, 0.72);
      default:
        spread(5, 0.95, sc: 0.8);
        shot(-20, 6, -150, -b * 0.9);
        shot(20, 6, 150, -b * 0.9);
    }
  }

  // ── Laser: feixes perfurantes num corredor estreito ──────────────────────

  void _fireLaser(BulletField f) {
    final lvl = game.weaponLevel;
    final offsets = switch (lvl) {
      1 => const [0.0],
      2 || 3 => const [-10.0, 10.0],
      4 || 5 => const [-16.0, 0.0, 16.0],
      _ => const [-22.0, -8.0, 8.0, 22.0],
    };
    // Dano por acerto; a perfuração faz o mesmo feixe cobrar de cada inimigo
    // na fila, então o valor unitário fica abaixo do vulcan.
    final dmg = 1.3 + 0.12 * lvl;
    for (final ox in offsets) {
      f.spawn(
        x: position.x + ox,
        y: position.y - 30,
        vx: 0,
        vy: -1120,
        shape: BulletShape.laser,
        color: 2,
        scale: 0.95,
        dmg: dmg,
        pierce: 2 + lvl ~/ 2,
      );
    }
  }

  // ── Mísseis: enxame teleguiado ───────────────────────────────────────────

  void _fireMissile(BulletField f) {
    final lvl = game.weaponLevel;
    final count = lvl >= 6 ? 8 : lvl + 1;
    for (var i = 0; i < count; i++) {
      // Saem em leque aberto (até para trás nos níveis altos) e curvam
      // sozinhos — o espetáculo do enxame fazendo a volta é o apelo da arma.
      final t = count == 1 ? 0.0 : (i / (count - 1)) - 0.5;
      final a = -math.pi / 2 + t * (1.1 + 0.28 * lvl);
      f.spawn(
        x: position.x + t * 30,
        y: position.y - 12,
        vx: math.cos(a) * 640,
        vy: math.sin(a) * 640,
        shape: BulletShape.dart,
        color: 1,
        scale: 0.78,
        dmg: 0.75,
        homing: 5.2,
      );
    }
  }

  void _fireOptions(BulletField f) {
    for (var i = 0; i < _optionCount; i++) {
      final ox = _optionPos[i].x;
      final oy = _optionPos[i].y - 10;
      switch (game.weaponType) {
        case WeaponType.vulcan:
          f.spawn(
            x: ox, y: oy, vx: 0, vy: -bulletSpeed,
            shape: BulletShape.laser, color: 3, scale: 0.6,
          );
        case WeaponType.laser:
          f.spawn(
            x: ox, y: oy, vx: 0, vy: -1120,
            shape: BulletShape.laser, color: 2, scale: 0.7,
            dmg: 1.1, pierce: 1,
          );
        case WeaponType.missile:
          f.spawn(
            x: ox, y: oy, vx: (i.isEven ? -1 : 1) * 420, vy: -420,
            shape: BulletShape.dart, color: 1, scale: 0.62,
            dmg: 0.6, homing: 5.2,
          );
      }
    }

    // Drones auxiliares (ALAS): sempre atiram reto para cima, independentes
    // do nível da arma — o "naves auxiliares sob demanda" pedido.
    if (wingmen) {
      for (var i = 0; i < 2; i++) {
        f.spawn(
          x: _wingPos[i].x,
          y: _wingPos[i].y - 10,
          vx: 0,
          vy: -bulletSpeed,
          shape: BulletShape.laser,
          color: 4,
          scale: 0.6,
          dmg: wingmenDamage,
        );
      }
    }
  }

  // ── Render ───────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final blink =
        invuln > 0 ? (math.sin(_t * 34) * 0.5 + 0.5) * 0.55 + 0.45 : 1.0;

    for (var i = 0; i < _optionCount; i++) {
      final rel = _optionPos[i] - position;
      _drawOption(canvas, Offset(rel.x, rel.y), blink);
    }
    // Drones auxiliares
    if (wingmen) {
      for (var i = 0; i < 2; i++) {
        final rel = _wingPos[i] - position;
        _drawWing(canvas, Offset(rel.x, rel.y), blink);
      }
    }

    canvas.drawCircle(
      Offset.zero,
      kGrazeRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = skin.accent.withValues(alpha: 0.20 * blink),
    );

    canvas.drawPath(
      Path()
        ..moveTo(-7, 16)
        ..lineTo(0, 34 + math.sin(_t * 30) * 5)
        ..lineTo(7, 16)
        ..close(),
      Paint()
        ..color = skin.accent.withValues(alpha: 0.85 * blink)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Casco: modelo 3D pre-renderizado por skin. Sem a folha no bundle, o
    // desenho vetorial de sempre assume — mesmo contrato do audio e dos ads.
    if (!sprites.draw(canvas, 'player_${skin.name}',
        size: 64, opacity: blink)) {
      final hull = Path()
        ..moveTo(0, -30)
        ..lineTo(15, 12)
        ..lineTo(6, 18)
        ..lineTo(-6, 18)
        ..lineTo(-15, 12)
        ..close();
      canvas.drawPath(
        hull,
        Paint()..color = skin.hull.withValues(alpha: blink),
      );
      // Contorno na cor de destaque da skin.
      canvas.drawPath(
        hull,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = skin.accent.withValues(alpha: blink),
      );
      for (final s in [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(s * 15, 12)
            ..lineTo(s * 25, 2)
            ..lineTo(s * 16, 4)
            ..close(),
          Paint()..color = skin.wing.withValues(alpha: blink),
        );
      }
    }

    canvas.drawCircle(
      Offset.zero,
      kPlayerHitRadius + 3.5,
      Paint()
        ..color = const Color(0xFFFF3B5C)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset.zero,
      kPlayerHitRadius,
      Paint()..color = Colors.white,
    );

    // Bolha do escudo, quando pronto.
    if (game.hasShield && game.shieldNotifier.value) {
      canvas.drawCircle(
        Offset.zero,
        30,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF35E1F5).withValues(alpha: 0.6 + 0.2 * math.sin(_t * 5)),
      );
      canvas.drawCircle(
        Offset.zero,
        30,
        Paint()..color = const Color(0xFF35E1F5).withValues(alpha: 0.08),
      );
    }
  }

  void _drawWing(Canvas canvas, Offset c, double blink) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final drew =
        sprites.draw(canvas, 'drone_wingman', size: 28, opacity: blink);
    canvas.restore();
    if (drew) return;
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..color = const Color(0xFF4BF07A).withValues(alpha: 0.35 * blink)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final d = Path()
      ..moveTo(c.dx, c.dy - 10)
      ..lineTo(c.dx + 7, c.dy + 6)
      ..lineTo(c.dx, c.dy + 2)
      ..lineTo(c.dx - 7, c.dy + 6)
      ..close();
    canvas.drawPath(d, Paint()..color = const Color(0xFFBFF7CE).withValues(alpha: blink));
    canvas.drawPath(
      d,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF4BF07A).withValues(alpha: blink),
    );
  }

  void _drawOption(Canvas canvas, Offset c, double blink) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final drew =
        sprites.draw(canvas, 'option_satellite', size: 24, opacity: blink);
    canvas.restore();
    if (drew) return;
    canvas.drawCircle(
      c,
      9,
      Paint()
        ..color = const Color(0xFF35E1F5).withValues(alpha: 0.4 * blink)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final d = Path()
      ..moveTo(c.dx, c.dy - 8)
      ..lineTo(c.dx + 6, c.dy)
      ..lineTo(c.dx, c.dy + 8)
      ..lineTo(c.dx - 6, c.dy)
      ..close();
    canvas.drawPath(
      d,
      Paint()..color = const Color(0xFF9BE8FF).withValues(alpha: blink),
    );
  }
}

/// Desenha a nave com uma skin e módulos, centrada na origem — para a prévia
/// do hangar, sem precisar de uma instância de jogo. Espelha `Player.render`.
void paintShipPreview(Canvas canvas, ShipSkin skin, Set<ShipModule> modules) {
  if (modules.contains(ShipModule.wingmen)) {
    for (final s in [-1.0, 1.0]) {
      final c = Offset(s * 30, 16);
      final w = Path()
        ..moveTo(c.dx, c.dy - 10)
        ..lineTo(c.dx + 7, c.dy + 6)
        ..lineTo(c.dx, c.dy + 2)
        ..lineTo(c.dx - 7, c.dy + 6)
        ..close();
      canvas.drawPath(w, Paint()..color = const Color(0xFFBFF7CE));
      canvas.drawPath(
        w,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF4BF07A),
      );
    }
  }

  canvas.drawPath(
    Path()
      ..moveTo(-7, 16)
      ..lineTo(0, 32)
      ..lineTo(7, 16)
      ..close(),
    Paint()
      ..color = skin.accent.withValues(alpha: 0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );

  final hull = Path()
    ..moveTo(0, -30)
    ..lineTo(15, 12)
    ..lineTo(6, 18)
    ..lineTo(-6, 18)
    ..lineTo(-15, 12)
    ..close();
  canvas.drawPath(hull, Paint()..color = skin.hull);
  canvas.drawPath(
    hull,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = skin.accent,
  );
  for (final s in [-1.0, 1.0]) {
    canvas.drawPath(
      Path()
        ..moveTo(s * 15, 12)
        ..lineTo(s * 25, 2)
        ..lineTo(s * 16, 4)
        ..close(),
      Paint()..color = skin.wing,
    );
  }
  canvas.drawCircle(Offset.zero, kPlayerHitRadius, Paint()..color = Colors.white);

  if (modules.contains(ShipModule.shield)) {
    canvas.drawCircle(
      Offset.zero,
      30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF35E1F5).withValues(alpha: 0.6),
    );
  }
}
