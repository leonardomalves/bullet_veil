import 'dart:math' as math;

import 'package:flame/components.dart';

import 'arena.dart';

/// O cérebro de ameaça: observa o jogador e aprende seus hábitos.
///
/// Duas leituras alimentam a mira dos inimigos:
///  1. **Velocidade** (EMA ~180ms) → tiro de interceptação: mira onde o
///     jogador VAI estar, não onde está. O counter-play é trocar de direção
///     depois do disparo — exatamente a dança que o gênero ensina.
///  2. **Hábito** (histograma de permanência em faixas de X, meia-vida ~8s)
///     → emboscada: com fúria alta, parte dos tiros vai para o canto
///     favorito, punindo quem sempre volta pro mesmo lugar.
///
/// A agressividade é a FÚRIA: jogador fraco enfrenta mira ingênua; jogador
/// dominando enfrenta um jogo que aprendeu a ler. Nunca passa de 85% de
/// antecipação — previsão perfeita não tem counter-play e vira injustiça.
class ThreatBrain {
  ThreatBrain(this._rng);

  final math.Random _rng;

  static const int bands = 9;
  static const double _maxLead = 0.85;
  static const double _emaTau = 0.18;
  static const double _dwellHalfLife = 8.0;

  final Vector2 _vel = Vector2.zero();
  final Vector2 _lastPos = Vector2.zero();
  final List<double> _dwell = List.filled(bands, 0);
  bool _hasLast = false;

  /// Agressividade da mira (0..1) — o jogo alimenta com o rank/Fúria.
  double aggression = 0;

  Vector2 get velocity => _vel.clone();

  void observe(double dt, Vector2 pos) {
    if (dt <= 0) return;
    if (_hasLast) {
      final k = (dt / _emaTau).clamp(0.0, 1.0);
      _vel.x += ((pos.x - _lastPos.x) / dt - _vel.x) * k;
      _vel.y += ((pos.y - _lastPos.y) / dt - _vel.y) * k;
    }
    _lastPos.setFrom(pos);
    _hasLast = true;

    final decay = math.pow(0.5, dt / _dwellHalfLife).toDouble();
    for (var i = 0; i < bands; i++) {
      _dwell[i] *= decay;
    }
    final b = (pos.x / kArenaWidth * bands).floor().clamp(0, bands - 1);
    _dwell[b] += dt;
  }

  /// Centro da faixa onde o jogador mais viveu — o "canto favorito".
  double get favoriteX {
    var best = 0;
    var bestV = -1.0;
    for (var i = 0; i < bands; i++) {
      if (_dwell[i] > bestV) {
        bestV = _dwell[i];
        best = i;
      }
    }
    return (best + 0.5) * kArenaWidth / bands;
  }

  /// Onde o jogador estará quando uma bala saída de [origin] a [bulletSpeed]
  /// chegar nele. Duas iterações refinam o encontro linear de sobra.
  Vector2 intercept(Vector2 origin, double bulletSpeed) {
    if (!_hasLast) return Vector2(kArenaWidth / 2, kPlayerMaxY);
    final lead = (aggression * _maxLead).clamp(0.0, _maxLead);
    if (lead <= 0 || bulletSpeed <= 0) return _lastPos.clone();

    var predicted = _lastPos.clone();
    for (var i = 0; i < 2; i++) {
      final t = math.min(predicted.distanceTo(origin) / bulletSpeed, 0.9);
      predicted
        ..setFrom(_lastPos)
        ..addScaled(_vel, t * lead);
    }
    predicted.x = predicted.x.clamp(kPlayerMinX, kPlayerMaxX);
    predicted.y = predicted.y.clamp(kPlayerMinY, kPlayerMaxY);
    return predicted;
  }

  /// Com fúria alta, ~30% das miras viram emboscada no canto favorito.
  bool rollAmbush() => aggression > 0.45 && _rng.nextDouble() < 0.30;
}

/// Piso de agressividade dos CHEFES por fase (0,1,2…): o chefe é o inimigo
/// que estudou você — já entra esperto (55%) e termina quase vidente (85%,
/// o teto do sistema). Independe da Fúria: chefe burro não existe.
double bossAggressionFloor(int phaseIndex) =>
    (0.55 + 0.15 * phaseIndex).clamp(0.0, 0.85);
