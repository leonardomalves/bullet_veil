import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'arena.dart';
import 'atlas.dart';

/// Pool de balas em arrays planos (struct-of-arrays), desenhado numa única
/// chamada `drawRawAtlas`.
///
/// Este arquivo é a razão de o jogo aguentar milhares de balas. As três
/// decisões que importam:
///
/// 1. **Nenhum componente por bala.** Um `Component` do Flame por bala custa
///    árvore, ciclo de vida e uma chamada de render cada. Aqui são arrays
///    primitivos e um só `render()`.
/// 2. **Remoção por troca com o último** (`swap-remove`), O(1), sem realocar
///    nem preservar ordem — ordem de bala é irrelevante.
/// 3. **Buffers pré-alocados** para os transforms; a cada frame só reescrevo
///    os `count*4` floats em uso, via `Float32List.view` sem cópia.
class BulletField extends Component {
  BulletField({
    required this.atlas,
    required this.capacity,
    this.additive = true,
  });

  final BulletAtlas atlas;
  final int capacity;

  /// Blend aditivo: balas sobrepostas somam brilho. É a assinatura visual do
  /// gênero e sai de graça na GPU.
  final bool additive;

  late final Float32List _x = Float32List(capacity);
  late final Float32List _y = Float32List(capacity);
  late final Float32List _vx = Float32List(capacity);
  late final Float32List _vy = Float32List(capacity);
  late final Float32List _ax = Float32List(capacity);
  late final Float32List _ay = Float32List(capacity);
  late final Float32List _rot = Float32List(capacity);
  late final Float32List _spin = Float32List(capacity);
  late final Float32List _scale = Float32List(capacity);
  late final Float32List _hitR = Float32List(capacity);
  late final Int32List _sprite = Int32List(capacity);
  late final Uint8List _grazed = Uint8List(capacity);

  late final Float32List _xform = Float32List(capacity * 4);
  late final Float32List _texRects = Float32List(capacity * 4);

  // Armas especiais do jogador:
  late final Float32List _dmg = Float32List(capacity); // dano por acerto
  late final Uint8List _pierce = Uint8List(capacity); // atravessa N inimigos
  late final Float32List _homing = Float32List(capacity); // rad/s de curva
  // Recarga entre acertos de UMA bala perfurante. Sem isto, uma bala rápida
  // sobreposta a um alvo grande (chefe) cobra dano todo frame e o derrete.
  late final Float32List _hitCd = Float32List(capacity);
  static const double _pierceHitCd = 0.1;

  /// Alvos que as balas teleguiadas perseguem (setado pelo jogo a cada frame).
  List<Offset> homingTargets = const [];

  late final Paint _paint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.low
    ..blendMode = additive ? BlendMode.plus : BlendMode.srcOver;

  int _count = 0;
  int get count => _count;
  bool get isFull => _count >= capacity;

  void spawn({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required BulletShape shape,
    required int color,
    double ax = 0,
    double ay = 0,
    double spin = 0,
    double scale = 1,
    bool faceVelocity = true,
    double? rotation,
    double dmg = 1,
    int pierce = 0,
    double homing = 0,
  }) {
    if (_count >= capacity) return; // degrada em densidade, não em framerate
    final i = _count++;

    _x[i] = x;
    _y[i] = y;
    _vx[i] = vx;
    _vy[i] = vy;
    _ax[i] = ax;
    _ay[i] = ay;
    // Sprites apontam para -Y, daí o +π/2 sobre o ângulo da velocidade.
    _rot[i] = rotation ??
        (faceVelocity ? math.atan2(vy, vx) + math.pi / 2 : 0.0);
    _spin[i] = spin;
    _scale[i] = scale;
    _hitR[i] = BulletAtlas.hitRadiusOf(shape) * scale;
    _sprite[i] = BulletAtlas.id(shape, color);
    _grazed[i] = 0;
    _dmg[i] = dmg;
    _pierce[i] = pierce.clamp(0, 250);
    _homing[i] = homing;
    _hitCd[i] = 0;
  }

  void _swapRemove(int i) {
    final last = --_count;
    if (i != last) {
      _x[i] = _x[last];
      _y[i] = _y[last];
      _vx[i] = _vx[last];
      _vy[i] = _vy[last];
      _ax[i] = _ax[last];
      _ay[i] = _ay[last];
      _rot[i] = _rot[last];
      _spin[i] = _spin[last];
      _scale[i] = _scale[last];
      _hitR[i] = _hitR[last];
      _sprite[i] = _sprite[last];
      _grazed[i] = _grazed[last];
      _dmg[i] = _dmg[last];
      _pierce[i] = _pierce[last];
      _homing[i] = _homing[last];
      _hitCd[i] = _hitCd[last];
    }
  }

  /// Curva a bala teleguiada em direção ao alvo mais próximo, limitada à taxa
  /// de giro dela — é o limite que impede o míssil de ser um acerto garantido.
  void _steer(int i, double dt) {
    final targets = homingTargets;
    if (targets.isEmpty) return;

    var bestD2 = double.infinity;
    var bx = 0.0, by = 0.0;
    for (final t in targets) {
      final dx = t.dx - _x[i];
      final dy = t.dy - _y[i];
      final d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        bx = dx;
        by = dy;
      }
    }

    final desired = math.atan2(by, bx);
    final current = math.atan2(_vy[i], _vx[i]);
    var diff = desired - current;
    while (diff > math.pi) {
      diff -= math.pi * 2;
    }
    while (diff < -math.pi) {
      diff += math.pi * 2;
    }

    final maxTurn = _homing[i] * dt;
    final turn = diff.clamp(-maxTurn, maxTurn);
    final speed = math.sqrt(_vx[i] * _vx[i] + _vy[i] * _vy[i]);
    final na = current + turn;
    _vx[i] = math.cos(na) * speed;
    _vy[i] = math.sin(na) * speed;
    _rot[i] = na + math.pi / 2;
  }

  @override
  void update(double dt) {
    var i = 0;
    while (i < _count) {
      if (_homing[i] > 0) _steer(i, dt);
      if (_hitCd[i] > 0) _hitCd[i] -= dt;
      _vx[i] += _ax[i] * dt;
      _vy[i] += _ay[i] * dt;
      final nx = _x[i] + _vx[i] * dt;
      final ny = _y[i] + _vy[i] * dt;

      if (nx < -kCullMargin ||
          nx > kArenaWidth + kCullMargin ||
          ny < -kCullMargin ||
          ny > kArenaHeight + kCullMargin) {
        _swapRemove(i);
        continue;
      }

      _x[i] = nx;
      _y[i] = ny;
      if (_spin[i] != 0) _rot[i] += _spin[i] * dt;
      i++;
    }
    _writeBuffers();
  }

  void _writeBuffers() {
    for (var i = 0; i < _count; i++) {
      writeRSTransform(
        _xform,
        i,
        _rot[i],
        _scale[i],
        BulletAtlas.cell / 2,
        BulletAtlas.cell / 2,
        _x[i],
        _y[i],
      );
      final r = atlas.rectAt(_sprite[i]);
      final j = i * 4;
      _texRects[j] = r.left;
      _texRects[j + 1] = r.top;
      _texRects[j + 2] = r.right;
      _texRects[j + 3] = r.bottom;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_count == 0) return;
    // Views sem cópia sobre a região em uso dos buffers.
    canvas.drawRawAtlas(
      atlas.image,
      Float32List.view(_xform.buffer, 0, _count * 4),
      Float32List.view(_texRects.buffer, 0, _count * 4),
      null,
      null,
      null,
      _paint,
    );
  }

  /// Testa todas as balas contra a nave.
  ///
  /// N balas × 1 alvo — linear e barato. O gênero nunca precisa de N².
  /// Retorna `true` se alguma acertou; conta grazes pelo callback.
  bool checkPlayer({
    required double px,
    required double py,
    required double hitRadius,
    required double grazeRadius,
    required void Function() onGraze,
    required bool vulnerable,
  }) {
    var hit = false;
    for (var i = 0; i < _count; i++) {
      final dx = _x[i] - px;
      final dy = _y[i] - py;
      final d2 = dx * dx + dy * dy;

      if (vulnerable && !hit) {
        final rr = hitRadius + _hitR[i];
        if (d2 <= rr * rr) hit = true;
      }
      if (_grazed[i] == 0) {
        final gr = grazeRadius + _hitR[i];
        if (d2 <= gr * gr) {
          _grazed[i] = 1;
          onGraze();
        }
      }
    }
    return hit;
  }

  /// Aplica as balas do jogador contra um alvo circular e retorna o DANO
  /// total. Bala comum é consumida no acerto; bala com perfuração atravessa
  /// (decrementa o contador e segue viva) — é o que faz o laser varar a fila.
  double hitCircle(double cx, double cy, double radius) {
    var damage = 0.0;
    var i = 0;
    while (i < _count) {
      final dx = _x[i] - cx;
      final dy = _y[i] - cy;
      final rr = radius + _hitR[i];
      if (dx * dx + dy * dy <= rr * rr) {
        // Bala perfurante em recarga atravessa sem cobrar de novo: impede o
        // "re-hit" a cada frame que fundia os chefes.
        if (_pierce[i] > 0 && _hitCd[i] > 0) {
          i++;
          continue;
        }
        damage += _dmg[i];
        if (_pierce[i] > 0) {
          _pierce[i]--;
          _hitCd[i] = _pierceHitCd;
          i++;
        } else {
          _swapRemove(i);
        }
        continue;
      }
      i++;
    }
    return damage;
  }

  /// Limpa a tela (bomba). Entrega as posições para virarem partículas.
  int clear(void Function(double x, double y, int sprite)? onCleared) {
    final n = _count;
    if (onCleared != null) {
      for (var i = 0; i < _count; i++) {
        onCleared(_x[i], _y[i], _sprite[i]);
      }
    }
    _count = 0;
    return n;
  }
}
