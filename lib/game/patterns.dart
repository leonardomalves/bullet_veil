import 'dart:math' as math;

import 'package:flame/components.dart';

import 'atlas.dart';
import 'brain.dart';
import 'bullet_field.dart';

final _rng = math.Random();

/// Contexto de disparo entregue aos padrões.
class FireContext {
  FireContext(this.field);

  final BulletField field;
  final Vector2 origin = Vector2.zero();
  final Vector2 target = Vector2.zero();

  /// Cérebro de ameaça: quando presente, os padrões MIRADOS interceptam a
  /// trajetória do jogador (e às vezes emboscam o canto favorito) em vez de
  /// mirar a posição atual.
  ThreatBrain? brain;

  /// Escala global de velocidade das balas, definida pelo jogo conforme a
  /// dificuldade sobe. É o que faz o começo ser mais lento sem reescrever
  /// cada padrão: cedo ≈ 0,7; no fim ≈ 1,0.
  double speedScale = 1.0;

  double get angleToTarget =>
      math.atan2(target.y - origin.y, target.x - origin.x);

  /// Ponto de mira inteligente para uma bala de [speed] (pré-escala): usa o
  /// cérebro se houver; senão degrada para o alvo ingênuo.
  Vector2 aimPoint(double speed) {
    final b = brain;
    if (b == null) return target;
    return b.rollAmbush()
        ? Vector2(b.favoriteX, target.y)
        : b.intercept(origin, speed * speedScale);
  }

  /// Ângulo até o [aimPoint].
  double angleAimed(double speed) {
    final p = aimPoint(speed);
    return math.atan2(p.y - origin.y, p.x - origin.x);
  }

  void bullet(
    double angle,
    double speed, {
    BulletShape shape = BulletShape.orb,
    int color = 0,
    double spin = 0,
    double scale = 1,
    double accel = 0,
  }) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    final sp = speed * speedScale;
    field.spawn(
      x: origin.x,
      y: origin.y,
      vx: c * sp,
      vy: s * sp,
      ax: c * accel * speedScale,
      ay: s * accel * speedScale,
      shape: shape,
      color: color,
      spin: spin,
      scale: scale,
    );
  }
}

abstract class FirePattern {
  /// Cada padrão administra seu próprio relógio; o inimigo só repassa o dt.
  void tick(double dt, FireContext c);
}

/// Anel completo, girando um pouco a cada onda.
///
/// O padrão mais didático do gênero: sempre existe uma brecha, e a rotação
/// entre ondas faz a brecha andar. Ensina o jogador a ler movimento, não a
/// memorizar posição.
class RingPattern extends FirePattern {
  RingPattern({
    this.count = 18,
    this.speed = 165,
    this.interval = 1.1,
    this.shape = BulletShape.orb,
    this.color = 2,
    this.rotationPerWave = 0.17,
  });

  final int count;
  final double speed;
  final double interval;
  final BulletShape shape;
  final int color;
  final double rotationPerWave;

  double _cd = 0.4;
  double _phase = 0;

  @override
  void tick(double dt, FireContext c) {
    _cd -= dt;
    if (_cd > 0) return;
    _cd = interval;
    for (var i = 0; i < count; i++) {
      c.bullet(_phase + i * math.pi * 2 / count, speed,
          shape: shape, color: color);
    }
    _phase += rotationPerWave;
  }
}

/// Espiral contínua: poucos braços girando sem parar.
///
/// Cria pressão constante em vez de picos. Combinado com um anel, força o
/// jogador a se mover sempre — o oposto de ficar parado num canto seguro.
class SpiralPattern extends FirePattern {
  SpiralPattern({
    this.arms = 3,
    this.speed = 210,
    this.rate = 0.075,
    this.angularSpeed = 2.1,
    this.shape = BulletShape.rice,
    this.color = 1,
  });

  final int arms;
  final double speed;
  final double rate;
  final double angularSpeed;
  final BulletShape shape;
  final int color;

  double _cd = 0;
  double _angle = 0;

  @override
  void tick(double dt, FireContext c) {
    _angle += angularSpeed * dt;
    _cd -= dt;
    if (_cd > 0) return;
    _cd = rate;
    for (var i = 0; i < arms; i++) {
      c.bullet(_angle + i * math.pi * 2 / arms, speed,
          shape: shape, color: color);
    }
  }
}

/// Leque mirado no jogador.
///
/// Este é o padrão que pune ficar parado: ele sempre aponta para onde o
/// jogador está. Obriga movimento lateral em vez de recuo.
class AimedFanPattern extends FirePattern {
  AimedFanPattern({
    this.count = 5,
    this.spread = 0.42,
    this.speed = 265,
    this.interval = 1.35,
    this.shape = BulletShape.dart,
    this.color = 0,
  });

  final int count;
  final double spread;
  final double speed;
  final double interval;
  final BulletShape shape;
  final int color;

  double _cd = 0.7;

  @override
  void tick(double dt, FireContext c) {
    _cd -= dt;
    if (_cd > 0) return;
    _cd = interval;
    // Mira inteligente: intercepta a trajetória (escala com a Fúria).
    final base = c.angleAimed(speed);
    for (var i = 0; i < count; i++) {
      final t = count == 1 ? 0.0 : (i / (count - 1)) - 0.5;
      c.bullet(base + t * spread, speed, shape: shape, color: color);
    }
  }
}

/// Parede horizontal com uma brecha.
///
/// Densidade alta mas solução única e óbvia — dá ao jogador um momento de
/// alívio cognitivo entre padrões que exigem leitura.
class WallPattern extends FirePattern {
  WallPattern({
    this.count = 15,
    this.speed = 175,
    this.interval = 1.7,
    this.color = 5,
  });

  final int count;
  final double speed;
  final double interval;
  final int color;

  double _cd = 1.0;

  @override
  void tick(double dt, FireContext c) {
    _cd -= dt;
    if (_cd > 0) return;
    _cd = interval;
    final gap = _rng.nextInt(count);
    for (var i = 0; i < count; i++) {
      if (i == gap || i == gap + 1) continue;
      final t = i / (count - 1);
      c.bullet(
        math.pi / 2 + (t - 0.5) * 0.95,
        speed,
        shape: BulletShape.orb,
        color: color,
      );
    }
  }
}

/// Flor: anel com velocidades alternadas, que se abre em pétalas.
class FlowerPattern extends FirePattern {
  FlowerPattern({
    this.petals = 24,
    this.interval = 1.6,
    this.color = 3,
  });

  final int petals;
  final double interval;
  final int color;

  double _cd = 0.9;
  double _phase = 0;

  @override
  void tick(double dt, FireContext c) {
    _cd -= dt;
    if (_cd > 0) return;
    _cd = interval;
    for (var i = 0; i < petals; i++) {
      final a = _phase + i * math.pi * 2 / petals;
      final fast = i.isEven;
      c.bullet(
        a,
        fast ? 235 : 145,
        shape: fast ? BulletShape.orb : BulletShape.bigOrb,
        color: fast ? color : (color + 3) % bulletColors.length,
        scale: fast ? 1.0 : 0.8,
        accel: fast ? -55 : 35,
      );
    }
    _phase += 0.31;
  }
}

/// Rajada mirada: N tiros retos em sequência curta na direção do jogador,
/// depois uma pausa longa.
///
/// É o padrão que responde ao feedback de "tiro tem que parecer tiro": lê-se
/// como uma metralhadora apontada, não como um vórtice. A pausa entre rajadas
/// é o que mantém a tela limpa.
class BurstPattern extends FirePattern {
  BurstPattern({
    this.shots = 3,
    this.gap = 0.13,
    this.rest = 1.7,
    this.speed = 300,
    this.shape = BulletShape.rice,
    this.color = 1,
  });

  final int shots;
  final double gap; // intervalo entre tiros da rajada
  final double rest; // pausa entre rajadas
  final double speed;
  final BulletShape shape;
  final int color;

  double _cd = 0.8;
  int _left = 0;
  double _aim = 0;

  @override
  void tick(double dt, FireContext c) {
    _cd -= dt;
    if (_cd > 0) return;
    if (_left == 0) {
      // Mira UMA vez por rajada (tiros paralelos) — mas mira ESPERTO: com
      // fúria, antecipa a trajetória ou embosca o canto favorito.
      _left = shots;
      _aim = c.angleAimed(speed);
    }
    c.bullet(_aim, speed, shape: shape, color: color);
    _left--;
    _cd = _left > 0 ? gap : rest;
  }
}

/// Salva vertical: colunas de tiros retos para baixo, saindo de bocas fixas
/// da nave. Lê-se como canhões disparando — linear e previsível de desviar.
class VolleyPattern extends FirePattern {
  VolleyPattern({
    this.offsets = const [-40.0, 40.0],
    this.speed = 260,
    this.interval = 1.4,
    this.shape = BulletShape.rice,
    this.color = 5,
    this.seek = false,
  });

  final List<double> offsets;
  final double speed;
  final double interval;
  final BulletShape shape;
  final int color;

  /// Colunas que "andam": o centro da salva desliza para onde o jogador VAI
  /// estar (proporcional à agressividade). É o aprendizado que se VÊ — os
  /// canhões do chefe passam a te perseguir.
  final bool seek;

  double _cd = 0.6;

  @override
  void tick(double dt, FireContext c) {
    _cd -= dt;
    if (_cd > 0) return;
    _cd = interval;
    final ox = c.origin.x;
    var shift = 0.0;
    final b = c.brain;
    if (seek && b != null) {
      final p = c.aimPoint(speed);
      shift = (p.x - ox).clamp(-140.0, 140.0) * b.aggression;
    }
    for (final o in offsets) {
      c.origin.x = ox + shift + o;
      c.bullet(math.pi / 2, speed, shape: shape, color: color);
    }
    c.origin.x = ox;
  }
}

/// Vários padrões ao mesmo tempo — como chefes de verdade fazem.
class CompositePattern extends FirePattern {
  CompositePattern(this.parts);

  final List<FirePattern> parts;

  @override
  void tick(double dt, FireContext c) {
    for (final p in parts) {
      p.tick(dt, c);
    }
  }
}
