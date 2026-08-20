import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'arena.dart';
import 'atlas.dart';
import 'brain.dart';
import 'danmaku_game.dart';
import 'difficulty.dart';
import 'patterns.dart';
import 'sprites.dart';

/// Como o inimigo se desloca. Separado do padrão de tiro de propósito: a
/// combinação livre de movimento × padrão multiplica a variedade sem escrever
/// um inimigo novo para cada caso.
abstract class Movement {
  /// Retorna `false` quando o inimigo terminou seu papel e deve sair de cena.
  bool tick(double dt, Enemy e);
}

/// Entra, para para atirar, e vai embora por baixo.
class DiveHoverLeave extends Movement {
  DiveHoverLeave({
    required this.stopY,
    this.hover = 5.0,
    this.speed = 210,
    this.drift = 0,
  });

  final double stopY;
  final double hover;
  final double speed;

  /// Deriva lateral senoidal enquanto está parado.
  final double drift;

  double _hovered = 0;
  double _t = 0;
  bool _leaving = false;
  double _baseX = 0;

  @override
  bool tick(double dt, Enemy e) {
    _t += dt;
    if (_leaving) {
      e.position.y += speed * 1.5 * dt;
      return e.position.y < kArenaHeight + 120;
    }
    if (e.position.y < stopY) {
      e.position.y = math.min(stopY, e.position.y + speed * dt);
      _baseX = e.position.x;
      return true;
    }
    _hovered += dt;
    if (drift != 0) e.position.x = _baseX + math.sin(_t * 1.1) * drift;
    if (_hovered >= hover) _leaving = true;
    return true;
  }
}

/// Atravessa a tela na horizontal.
class SweepAcross extends Movement {
  SweepAcross({required this.speed, required this.bobAmplitude});

  final double speed;
  final double bobAmplitude;

  double _t = 0;
  double _baseY = -1;

  @override
  bool tick(double dt, Enemy e) {
    _t += dt;
    if (_baseY < 0) _baseY = e.position.y;
    e.position.x += speed * dt;
    e.position.y = _baseY + math.sin(_t * 2.2) * bobAmplitude;
    return e.position.x > -140 && e.position.x < kArenaWidth + 140;
  }
}

/// Kamikaze: desce reto, trava no jogador e MERGULHA. O aviso é o tremor
/// antes do bote — telegrafado o bastante para ser justo.
class KamikazeDive extends Movement {
  KamikazeDive({this.lockY = 320, this.diveSpeed = 560});

  final double lockY;
  final double diveSpeed;

  bool _locked = false;
  double _shiver = 0;
  final _dir = Vector2(0, 1);

  bool get locked => _locked;

  @override
  bool tick(double dt, Enemy e) {
    if (!_locked) {
      e.position.y += 170 * dt;
      if (e.position.y >= lockY) {
        _locked = true;
        // Mergulha para ONDE o jogador vai estar, não onde está — e nunca
        // mira como recruta: o kamikaze é comprometimento total.
        final b = e.game.brain;
        final saved = b.aggression;
        b.aggression = math.max(saved, 0.5);
        final aim = b.intercept(e.position, diveSpeed);
        b.aggression = saved;
        _dir
          ..setFrom(aim - e.position)
          ..normalize();
      }
      return e.position.y < kArenaHeight + 60;
    }
    _shiver += dt;
    if (_shiver < 0.28) {
      // tremida de aviso antes do mergulho
      e.position.x += math.sin(_shiver * 70) * 2.2;
      return true;
    }
    e.position.x += _dir.x * diveSpeed * dt;
    e.position.y += _dir.y * diveSpeed * dt;
    return e.position.y < kArenaHeight + 80 &&
        e.position.x > -80 &&
        e.position.x < kArenaWidth + 80;
  }
}

/// Chefe: desce, e depois oscila devagar sem sair.
class BossHold extends Movement {
  BossHold({required this.stopY, this.sway = 150});

  final double stopY;
  final double sway;

  double _t = 0;
  final double _centerX = kArenaWidth / 2;

  @override
  bool tick(double dt, Enemy e) {
    if (e.position.y < stopY) {
      e.position.y = math.min(stopY, e.position.y + 130 * dt);
      return true;
    }
    _t += dt;
    e.position.x = _centerX + math.sin(_t * 0.55) * sway;
    return true;
  }
}

/// Uma fase de chefe: ativa quando a vida cai a/abaixo de [at] (fração).
/// A primeira tem `at: 1.0` (começo). Trocar de fase troca o padrão de tiro —
/// é o que faz a luta escalar em vez de repetir.
class BossPhase {
  const BossPhase(this.at, this.pattern);
  final double at;
  final FirePattern pattern;
}

/// Arquétipos de chefe — cada um com silhueta e arsenal próprios, ciclando
/// por estágio. Resposta ao "o chefe parece só uma bola".
enum BossType { dreadnought, mantis, core }

extension BossTypeUi on BossType {
  String get label => switch (this) {
        BossType.dreadnought => 'ENCOURAÇADO',
        BossType.mantis => 'MANTIS',
        BossType.core => 'NÚCLEO',
      };

  String get callSign => switch (this) {
        BossType.dreadnought => 'ENCOURAÇADO "VULKAN"',
        BossType.mantis => 'MANTIS CEIFEIRA',
        BossType.core => 'NÚCLEO ORÁCULO',
      };
}

/// Nome de guerra do chefe do estágio; ciclos seguintes viram MK-II, MK-III…
String bossTitle(int stage) {
  final type = BossType.values[(stage - 1) % BossType.values.length];
  final cycle = (stage - 1) ~/ BossType.values.length;
  return cycle == 0 ? type.callSign : '${type.callSign} MK-${cycle + 1}';
}

/// Comportamentos especiais além do par movimento×padrão.
enum EnemyRole { normal, sniper }

class Enemy extends PositionComponent with HasGameReference<DanmakuGame> {
  Enemy({
    required super.position,
    required this.hp,
    required this.radius,
    required this.movement,
    required this.color,
    this.pattern,
    this.scoreValue = 250,
    this.isBoss = false,
    this.phases,
    this.bossType,
    this.role = EnemyRole.normal,
    this.elite = false,
    this.medalCarrier = false,
    this.formationId,
    this.spriteName,
    this.spriteSize = 0,
  })  : maxHp = hp,
        super(priority: 5);

  double hp;
  final double maxHp;
  final double radius;
  FirePattern? pattern;
  final Movement movement;
  final Color color;
  final int scoreValue;
  final bool isBoss;
  final List<BossPhase>? phases;
  final BossType? bossType;
  final EnemyRole role;

  /// Mid-boss: versão de elite, HUD dá destaque e a morte paga mais.
  final bool elite;

  /// Cargueiro: morrer derruba uma chuva de medalhas.
  final bool medalCarrier;

  /// Membro de formação: aniquilar o grupo inteiro paga bônus.
  final int? formationId;

  /// Folha renderizada a partir do modelo 3D (ver docs/render-sprites-offline).
  /// Nula, ou ausente do bundle, e o desenho volta a ser vetorial.
  final String? spriteName;

  /// Lado do quadrado do sprite, na resolução virtual da arena.
  final double spriteSize;

  double _flash = 0;
  double _spin = 0;
  bool _dying = false;
  bool _killed = false;
  int _phaseIndex = 0;

  // Sequência de morte do chefe (explosões encadeadas antes do estouro).
  double _deathT = 0;
  double _deathTick = 0;
  static const _deathDuration = 1.6;

  // Sniper: trava → telegrafa → dispara.
  double _aimT = 0;
  final Vector2 _aimDir = Vector2(0, 1);
  bool _aiming = false;

  bool get dying => _dying;
  double get hpFraction => (hp / maxHp).clamp(0.0, 1.0);
  int get phaseCount => phases?.length ?? 1;

  void damage(double amount) {
    if (_dying) return;
    hp -= amount;
    _flash = 0.09;
    _advancePhase();
    if (hp <= 0) {
      _dying = true;
      if (isBoss) {
        // Chefe não evapora: morre em sequência, com direito a agonia.
        game.onBossDying(this);
        return;
      }
      _killed = true;
      game.onEnemyKilled(this);
      removeFromParent();
    }
  }

  @override
  void onRemove() {
    // Fugiu (não foi morto): quebra a formação — o bônus exige aniquilação.
    if (!_killed && formationId != null) {
      game.onFormationBroken(formationId!);
    }
    super.onRemove();
  }

  void _advancePhase() {
    final ph = phases;
    if (ph == null) return;
    final frac = hpFraction;
    while (_phaseIndex < ph.length - 1 && frac <= ph[_phaseIndex + 1].at) {
      _phaseIndex++;
      pattern = ph[_phaseIndex].pattern;
      _flash = 0.22;
      game.onBossPhase(this, _phaseIndex);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _spin += dt * (isBoss ? 0.5 : 1.6);
    if (_flash > 0) _flash -= dt;

    // Agonia do chefe: deriva lenta + explosões encadeadas → estouro final.
    if (_dying) {
      position.y += 14 * dt;
      _deathT += dt;
      _deathTick -= dt;
      if (_deathTick <= 0) {
        _deathTick = 0.13;
        game.onBossDeathTick(this);
      }
      if (_deathT >= _deathDuration) {
        _killed = true;
        game.onEnemyKilled(this);
        removeFromParent();
      }
      return;
    }

    if (!movement.tick(dt, this)) {
      removeFromParent();
      return;
    }

    // Só atira depois de entrar na tela: bala nascendo fora da vista é
    // injusta, o jogador não teve como ver de onde veio.
    if (position.y > 40) {
      // Piso de inteligência: chefe JÁ ENTRA esperto (e afia por fase);
      // elite e sniper também não miram como recruta. A Fúria só soma.
      final b = game.brain;
      final saved = b.aggression;
      if (isBoss) {
        b.aggression = math.max(saved, bossAggressionFloor(_phaseIndex));
      } else if (elite || role == EnemyRole.sniper) {
        b.aggression = math.max(saved, 0.45);
      }
      if (role == EnemyRole.sniper) {
        _tickSniper(dt);
      } else if (pattern != null) {
        final ctx = game.fireContext;
        ctx.origin.setValues(position.x, position.y);
        ctx.target.setFrom(game.player.position);
        pattern!.tick(dt, ctx);
      }
      b.aggression = saved;
    }
  }

  /// Sniper: 0.8s de mira TELEGRAFADA (linha fina até o ponto travado) e três
  /// dardos rápidos naquela linha. Mortal, mas 100% legível.
  void _tickSniper(double dt) {
    _aimT += dt;
    if (!_aiming) {
      if (_aimT >= 1.4) {
        _aiming = true;
        _aimT = 0;
        // Trava na INTERCEPTAÇÃO — a linha telegrafada mostra a previsão,
        // e fugir dela é exatamente o counter-play.
        final aim = game.brain
            .intercept(position, 470 * game.fireContext.speedScale);
        _aimDir
          ..setFrom(aim - position)
          ..normalize();
        game.onSniperLock(this);
      }
      return;
    }
    if (_aimT >= 0.8) {
      _aiming = false;
      _aimT = 0;
      game.sniperFire(this, _aimDir);
    }
  }

  @override
  void render(Canvas canvas) {
    final r = radius;
    final flashing = _flash > 0;
    final base = flashing ? Colors.white : color;

    // Linha de mira do sniper: o aviso É o desenho.
    if (role == EnemyRole.sniper && _aiming) {
      final blink = 0.35 + 0.4 * (math.sin(_aimT * 34) * 0.5 + 0.5);
      canvas.drawLine(
        Offset.zero,
        Offset(_aimDir.x * 1500, _aimDir.y * 1500),
        Paint()
          ..strokeWidth = 2.2
          ..color = const Color(0xFFFF3B5C).withValues(alpha: blink),
      );
    }

    canvas.drawCircle(
      Offset.zero,
      r * 1.2,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
    );

    // Anel de elite: mid-boss se anuncia.
    if (elite) {
      canvas.drawCircle(
        Offset.zero,
        r * 1.35,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFD23F)
              .withValues(alpha: 0.5 + 0.3 * math.sin(_spin * 3)),
      );
    }

    if (_renderSprite(canvas, flashing)) return;

    if (isBoss) {
      _renderBoss(canvas, r, base);
    } else {
      _renderShip(canvas, r, base, flashing);
    }
  }

  /// Desenha o modelo 3D pré-renderizado (ver `docs/render-sprites-offline.md`),
  /// tingido com a cor de paleta DESTE inimigo — é o que faz um único modelo
  /// neutro atender aos vários tons em que o mesmo arquétipo aparece.
  ///
  /// Devolve `false` quando a folha não está no bundle; aí o vetor assume e o
  /// jogo continua idêntico ao que sempre foi.
  bool _renderSprite(Canvas canvas, bool flashing) {
    final name = spriteName;
    if (name == null || spriteSize <= 0) return false;

    // O NÚCLEO gira: a folha dele cobre 45° em 12 frames, e o anel tem
    // simetria de 8, então esse arco já fecha a volta inteira.
    final sheet = sprites[name];
    var frame = 0;
    if (sheet != null && sheet.count > 1) {
      const arc = math.pi / 4;
      frame = ((_spin % arc) / arc * sheet.count).floor();
    }

    // O corredor cruza a tela nos dois sentidos e o modelo tem motor num
    // extremo só: sem espelhar, metade das aparições voa de ré.
    final mv = movement;
    final mirror = mv is SweepAcross && mv.speed < 0;
    if (mirror) canvas.scale(-1, 1);
    final ok = sprites.draw(
      canvas,
      name,
      size: spriteSize,
      frame: frame,
      tint: flashing ? Colors.white : color,
      tintMode: flashing ? BlendMode.srcATop : BlendMode.modulate,
    );
    if (mirror) canvas.scale(-1, 1);
    if (!ok) return false;

    // Cabine por cima do sprite: marca o centro real da colisão, e precisa
    // ser constante em qualquer escala — por isso nunca foi para o modelo.
    canvas.drawCircle(
      Offset(0, isBoss ? 0 : -radius * 0.05),
      radius * (isBoss ? 0.22 : 0.26),
      Paint()..color = flashing ? color : Colors.white.withValues(alpha: 0.92),
    );
    return true;
  }

  /// Caça inimigo apontado para BAIXO (na direção do jogador). O núcleo claro
  /// marca o centro real da colisão — mesma regra de leitura das balas.
  void _renderShip(Canvas canvas, double r, Color base, bool flashing) {
    final wingPaint = Paint()..color = base.withValues(alpha: 0.9);

    Path wing(double dir) => Path()
      ..moveTo(dir * r * 0.22, -r * 0.12)
      ..lineTo(dir * r * 1.02, -r * 0.48)
      ..lineTo(dir * r * 0.86, r * 0.20)
      ..lineTo(dir * r * 0.20, r * 0.24)
      ..close();
    canvas.drawPath(wing(-1), wingPaint);
    canvas.drawPath(wing(1), wingPaint);

    // Fuselagem com o nariz para baixo.
    final body = Path()
      ..moveTo(0, r)
      ..lineTo(r * 0.44, -r * 0.32)
      ..lineTo(0, -r * 0.6)
      ..lineTo(-r * 0.44, -r * 0.32)
      ..close();
    canvas.drawPath(body, Paint()..color = base);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..color = Colors.white.withValues(alpha: 0.7),
    );

    // Cabine / núcleo de dano.
    canvas.drawCircle(
      Offset(0, -r * 0.05),
      r * 0.26,
      Paint()..color = flashing ? base : Colors.white.withValues(alpha: 0.92),
    );
  }

  void _renderBoss(Canvas canvas, double r, Color base) {
    switch (bossType ?? BossType.core) {
      case BossType.dreadnought:
        _renderDreadnought(canvas, r, base);
      case BossType.mantis:
        _renderMantis(canvas, r, base);
      case BossType.core:
        _renderCore(canvas, r, base);
    }
    // Cabine/núcleo comum, marca o alvo.
    canvas.drawCircle(
      Offset.zero,
      r * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  /// ENCOURAÇADO: nave-mãe larga e angular, com casco em camadas e canhões.
  void _renderDreadnought(Canvas canvas, double r, Color base) {
    final hull = Path()
      ..moveTo(0, r * 0.9)
      ..lineTo(r * 1.35, r * 0.2)
      ..lineTo(r * 1.1, -r * 0.55)
      ..lineTo(r * 0.4, -r * 0.85)
      ..lineTo(-r * 0.4, -r * 0.85)
      ..lineTo(-r * 1.1, -r * 0.55)
      ..lineTo(-r * 1.35, r * 0.2)
      ..close();
    canvas.drawPath(hull, Paint()..color = base);
    canvas.drawPath(
      hull,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..color = Colors.white.withValues(alpha: 0.6),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, r * 0.5)
        ..lineTo(r * 0.7, -r * 0.4)
        ..lineTo(-r * 0.7, -r * 0.4)
        ..close(),
      Paint()..color = Color.lerp(base, Colors.black, 0.35)!,
    );
    for (final s in [-1.0, 1.0]) {
      canvas.drawRect(
        Rect.fromLTWH(s * r * 0.9 - r * 0.1, r * 0.2, r * 0.2, r * 0.5),
        Paint()..color = Color.lerp(base, Colors.white, 0.3)!,
      );
    }
  }

  /// MANTIS: caça esguio com asas em foice que batem devagar (via _spin).
  void _renderMantis(Canvas canvas, double r, Color base) {
    final sweep = math.sin(_spin) * 0.25;
    for (final s in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(0, -r * 0.2);
      canvas.rotate(s * (0.5 + sweep));
      final wing = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(r * 1.1, -r * 0.3, r * 1.5, r * 0.5)
        ..quadraticBezierTo(r * 0.8, r * 0.1, 0, r * 0.3)
        ..close();
      canvas.drawPath(wing, Paint()..color = base.withValues(alpha: 0.92));
      canvas.drawPath(
        wing,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05
          ..color = Colors.white.withValues(alpha: 0.5),
      );
      canvas.restore();
    }
    final body = Path()
      ..moveTo(0, r * 1.1)
      ..lineTo(r * 0.3, -r * 0.6)
      ..lineTo(0, -r * 0.95)
      ..lineTo(-r * 0.3, -r * 0.6)
      ..close();
    canvas.drawPath(
        body, Paint()..color = Color.lerp(base, Colors.white, 0.15)!);
  }

  /// NÚCLEO: fortaleza orbital — anel de segmentos girando + olho central.
  void _renderCore(Canvas canvas, double r, Color base) {
    canvas.save();
    canvas.rotate(_spin);
    const seg = 8;
    for (var i = 0; i < seg; i++) {
      canvas.save();
      canvas.rotate(i * math.pi * 2 / seg);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(r * 0.92, 0), width: r * 0.5, height: r * 0.32),
          Radius.circular(r * 0.1),
        ),
        Paint()..color = base.withValues(alpha: 0.92),
      );
      canvas.restore();
    }
    canvas.restore();
    canvas.drawCircle(
      Offset.zero,
      r * 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Color.lerp(base, Colors.black, 0.3)!,
    );
    canvas.drawCircle(Offset.zero, r * 0.44, Paint()..color = base);
  }
}

/// Fábrica dos arquétipos, parametrizada pela dificuldade escolhida.
///
/// A dificuldade mexe em dois eixos por aqui: HP (×[hpMul]) e densidade dos
/// padrões cheios (+[densityDelta] balas em anel/parede/chefe). A velocidade
/// das balas escala fora, no `FireContext.speedScale`.
class EnemyFactory {
  EnemyFactory(this.cfg);

  final DifficultyConfig cfg;

  /// Escala de vida por avanço, setada pelo jogo a cada onda. Faz os inimigos
  /// comuns ficarem mais duros conforme o jogo progride — o "vem inimigo mais
  /// forte" pedido. Cresce ~5%/onda, com teto.
  double waveScale = 1.0;

  double _hp(double base) => base * cfg.hpMul * waveScale;

  int _dense(int base, {int min = 5}) =>
      math.max(min, base + cfg.densityDelta);

  /// Inimigo de tutorial: pouca vida, um tiro mirado lento de vez em quando.
  /// É o que faz as primeiras ondas ensinarem em vez de matar.
  Enemy easyGrunt(double x, {int colorIndex = 2}) => Enemy(
        position: Vector2(x, -60),
        hp: _hp(14),
        radius: 21,
        color: bulletColors[colorIndex],
        pattern: AimedFanPattern(count: 1, interval: 2.0, speed: 190),
        movement: DiveHoverLeave(stopY: 190, hover: 2.0, drift: 55),
        scoreValue: 140,
        spriteName: 'enemy_grunt',
        spriteSize: 52,
      );

  Enemy grunt(double x, {int colorIndex = 2}) => Enemy(
        position: Vector2(x, -60),
        hp: _hp(22),
        radius: 22,
        color: bulletColors[colorIndex],
        pattern: AimedFanPattern(
          count: cfg.densityDelta >= 3 ? 3 : 2,
          interval: 1.8,
          speed: 235,
        ),
        movement: DiveHoverLeave(stopY: 210, hover: 2.4, drift: 70),
        scoreValue: 180,
        spriteName: 'enemy_grunt',
        spriteSize: 52,
      );

  /// Metralhador: rajadas retas miradas no jogador. (Antes era espiral —
  /// trocado por tiro linear a pedido: parece tiro, não vórtice.)
  Enemy spinner(double x, {int colorIndex = 1}) => Enemy(
        position: Vector2(x, -70),
        hp: _hp(46),
        radius: 27,
        color: bulletColors[colorIndex],
        pattern: BurstPattern(
          shots: 4,
          gap: 0.1,
          rest: 1.5,
          speed: 300,
          color: colorIndex,
        ),
        movement: DiveHoverLeave(stopY: 260, hover: 4.5, drift: 110),
        scoreValue: 420,
        spriteName: 'enemy_spinner',
        spriteSize: 64,
      );

  /// Canhoneiro: colunas retas de tiros para baixo. (Antes era anel.)
  Enemy ringer(double x, {int colorIndex = 3}) => Enemy(
        position: Vector2(x, -70),
        hp: _hp(60),
        radius: 30,
        color: bulletColors[colorIndex],
        pattern: VolleyPattern(
          offsets: const [-34, 0, 34],
          speed: 265,
          interval: 1.5,
          color: colorIndex,
        ),
        movement: DiveHoverLeave(stopY: 300, hover: 5.5),
        scoreValue: 560,
        spriteName: 'enemy_ringer',
        spriteSize: 72,
      );

  Enemy runner(double y, bool fromLeft, {int colorIndex = 5}) => Enemy(
        position: Vector2(fromLeft ? -80 : kArenaWidth + 80, y),
        hp: _hp(30),
        radius: 20,
        color: bulletColors[colorIndex],
        pattern: WallPattern(
          count: _dense(8, min: 4),
          interval: 1.7,
          color: colorIndex,
        ),
        movement: SweepAcross(
          speed: fromLeft ? 175 : -175,
          bobAmplitude: 45,
        ),
        scoreValue: 300,
        spriteName: 'enemy_runner',
        spriteSize: 48,
      );

  /// Encouraçado: muito HP, grande, fica em cena despejando anel + leque
  /// mirado. O "inimigo mais forte" que entra nas ondas avançadas e força o
  /// jogador a comprometer dano (ou uma bomba) em vez de limpar num passe.
  Enemy heavy(double x, {int colorIndex = 0}) => Enemy(
        position: Vector2(x, -90),
        hp: _hp(170),
        radius: 36,
        color: bulletColors[colorIndex],
        pattern: CompositePattern([
          VolleyPattern(
            offsets: const [-50, -25, 25, 50],
            speed: 250,
            interval: 1.9,
            color: colorIndex,
          ),
          BurstPattern(shots: 3, rest: 1.7, speed: 280, color: 0),
        ]),
        movement: DiveHoverLeave(stopY: 230, hover: 8, drift: 45),
        scoreValue: 1200,
        spriteName: 'enemy_heavy',
        spriteSize: 84,
      );

  /// Sniper: fica no alto, telegrafa uma linha e dispara dardos nela.
  /// Estreia no estágio 2 — o primeiro inimigo que pune ficar parado.
  Enemy sniper(double x) => Enemy(
        position: Vector2(x, -60),
        hp: _hp(34),
        radius: 22,
        color: bulletColors[2],
        role: EnemyRole.sniper,
        movement: DiveHoverLeave(stopY: 170, hover: 9, drift: 30, speed: 240),
        scoreValue: 520,
        spriteName: 'enemy_sniper',
        spriteSize: 52,
      );

  /// Kamikaze: barato, rápido, explode em cima de quem dorme no ponto.
  /// Estreia no estágio 3.
  Enemy kamikaze(double x) => Enemy(
        position: Vector2(x, -50),
        hp: _hp(10),
        radius: 18,
        color: bulletColors[0],
        movement: KamikazeDive(),
        scoreValue: 240,
        spriteName: 'enemy_kamikaze',
        spriteSize: 44,
      );

  /// Cargueiro: lento, gordo, SEM tiro — uma piñata de medalhas atravessando
  /// a tela. Matar antes de fugir alimenta a corrente. Estreia no estágio 4.
  Enemy freighter(bool fromLeft, {double y = 210}) => Enemy(
        position: Vector2(fromLeft ? -100 : kArenaWidth + 100, y),
        hp: _hp(240),
        radius: 34,
        color: bulletColors[5],
        medalCarrier: true,
        movement: SweepAcross(speed: fromLeft ? 72 : -72, bobAmplitude: 18),
        scoreValue: 900,
        spriteName: 'enemy_freighter',
        spriteSize: 80,
      );

  /// Mid-boss (ELITE): o pedágio do meio do estágio. Sem fases, mas grosso o
  /// bastante para exigir compromisso — e paga arma garantida.
  Enemy midBoss(int stage) => Enemy(
        position: Vector2(kArenaWidth / 2, -100),
        hp: (380 + stage * 170) * cfg.hpMul,
        radius: 42,
        color: bulletColors[5],
        elite: true,
        pattern: CompositePattern([
          VolleyPattern(
            offsets: const [-60, -20, 20, 60],
            speed: 265,
            interval: 1.6,
            color: 5,
            seek: true,
          ),
          BurstPattern(shots: 4, gap: 0.09, rest: 1.4, speed: 330, color: 7),
        ]),
        movement: DiveHoverLeave(stopY: 250, hover: 14, drift: 120),
        scoreValue: 2600 + stage * 400,
        spriteName: 'enemy_elite',
        spriteSize: 104,
      );

  /// Formação em V de 5 naves. Aniquilar TODAS antes de alguma fugir paga
  /// bônus — a lição de Galaga, intacta desde 1981.
  List<Enemy> formationV(int formationId, {int colorIndex = 3}) {
    const cx = kArenaWidth / 2;
    const spread = 105.0;
    final out = <Enemy>[];
    for (var i = 0; i < 5; i++) {
      final k = i - 2; // -2..2
      out.add(Enemy(
        position: Vector2(cx + k * spread, -60 - k.abs() * 70),
        hp: _hp(16),
        radius: 20,
        color: bulletColors[colorIndex],
        formationId: formationId,
        pattern: AimedFanPattern(count: 1, interval: 2.6, speed: 210),
        movement: DiveHoverLeave(
          stopY: 180 + k.abs() * 62,
          hover: 3.6,
          drift: 40,
        ),
        scoreValue: 160,
        spriteName: 'enemy_grunt',
        spriteSize: 52,
      ));
    }
    return out;
  }

  Enemy boss(int stage) {
    // O tipo cicla por estágio, cada um com silhueta e arsenal próprios.
    final type = BossType.values[(stage - 1) % BossType.values.length];
    final phases = _bossPhases(type);

    // Vida cresce MUITO por estágio: o 1º já é um combate, e cada estágio
    // dobra a aposta. (Não usa waveScale — o estágio é a régua dele.)
    final hp = (2200 + (stage - 1) * 1500) * cfg.hpMul;
    final color = switch (type) {
      BossType.dreadnought => bulletColors[7], // laranja: nave-mãe pesada
      BossType.mantis => bulletColors[4], // verde: caça ágil
      BossType.core => bulletColors[1], // magenta: fortaleza orbital
    };
    final radius = switch (type) {
      BossType.dreadnought => 64.0,
      BossType.mantis => 52.0,
      BossType.core => 58.0,
    };
    final sprite = switch (type) {
      BossType.dreadnought => ('boss_dreadnought', 180.0),
      BossType.mantis => ('boss_mantis', 164.0),
      BossType.core => ('boss_core', 148.0),
    };
    return Enemy(
      position: Vector2(kArenaWidth / 2, -140),
      hp: hp,
      radius: radius,
      color: color,
      isBoss: true,
      bossType: type,
      scoreValue: 8000 + (stage - 1) * 4000,
      pattern: phases.first.pattern,
      phases: phases,
      movement: BossHold(stopY: 250, sway: type == BossType.mantis ? 210 : 150),
      spriteName: sprite.$1,
      spriteSize: sprite.$2,
    );
  }

  /// Movesets de chefe por tipo. Tudo em tiro linear, exceto a flor do Núcleo
  /// — que é a assinatura de uma fortaleza orbital, o único radial que sobra.
  List<BossPhase> _bossPhases(BossType type) {
    switch (type) {
      case BossType.dreadnought:
        // Muralhas de canhão + rajadas miradas. Lento, pesado, previsível.
        return [
          BossPhase(1.0, CompositePattern([
            VolleyPattern(
                offsets: const [-90, -45, 45, 90],
                speed: 250, interval: 1.7, seek: true),
            BurstPattern(shots: 3, rest: 2.0, speed: 300, color: 0),
          ])),
          BossPhase(0.6, CompositePattern([
            VolleyPattern(
                offsets: const [-110, -70, -30, 30, 70, 110],
                speed: 270, interval: 1.4, seek: true),
            BurstPattern(shots: 4, gap: 0.1, rest: 1.6, speed: 320, color: 0),
          ])),
          BossPhase(0.3, CompositePattern([
            VolleyPattern(
                offsets: const [-120, -90, -60, -30, 0, 30, 60, 90, 120],
                speed: 300, interval: 1.15, seek: true),
            BurstPattern(shots: 5, gap: 0.08, rest: 1.3, speed: 360, color: 0),
          ])),
        ];
      case BossType.mantis:
        // Ágil e agressivo: rajadas rápidas miradas + leques curtos.
        return [
          BossPhase(1.0, CompositePattern([
            BurstPattern(shots: 3, gap: 0.09, rest: 1.2, speed: 340, color: 4),
            AimedFanPattern(count: 3, interval: 1.8, spread: 0.4, color: 0),
          ])),
          BossPhase(0.6, CompositePattern([
            BurstPattern(shots: 5, gap: 0.08, rest: 1.0, speed: 380, color: 4),
            AimedFanPattern(count: 5, interval: 1.5, spread: 0.6, color: 0),
          ])),
          BossPhase(0.3, CompositePattern([
            BurstPattern(shots: 6, gap: 0.07, rest: 0.8, speed: 420, color: 4),
            AimedFanPattern(count: 7, interval: 1.2, spread: 0.8, color: 6),
          ])),
        ];
      case BossType.core:
        // Fortaleza orbital: a flor/leque radial é a assinatura dela, com
        // rajadas miradas para pontuar. Densa, mas legível.
        return [
          BossPhase(1.0, CompositePattern([
            FlowerPattern(petals: _dense(12, min: 10), interval: 2.3),
            BurstPattern(shots: 3, rest: 2.0, speed: 300, color: 0),
          ])),
          BossPhase(0.6, CompositePattern([
            FlowerPattern(petals: _dense(14, min: 12), interval: 1.9),
            AimedFanPattern(count: 5, interval: 2.0, spread: 0.8, color: 0),
          ])),
          BossPhase(0.3, CompositePattern([
            FlowerPattern(petals: _dense(16, min: 14), interval: 1.5),
            BurstPattern(shots: 4, gap: 0.08, rest: 1.3, speed: 340, color: 6),
          ])),
        ];
    }
  }
}
