import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vibração tátil com throttle.
///
/// No celular o tato é metade do "juice": abate leve, dano pesado. Mas motor
/// de vibração saturado vira zumbido — daí o intervalo mínimo por intensidade.
class Haptics {
  Haptics._();

  static final Haptics instance = Haptics._();

  static const _prefsKey = 'bv.haptics';

  final _clock = Stopwatch()..start();
  int _lastLight = -1000;
  int _lastMedium = -1000;
  int _lastHeavy = -1000;

  bool _enabled = true;

  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_prefsKey, value))
        .ignore();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? true;
  }

  /// Abates, coletas — o tic-tic constante da colheita.
  void light() {
    if (!_enabled) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastLight < 110) return;
    _lastLight = now;
    _fire(HapticFeedback.lightImpact);
  }

  /// Eventos de progressão: arma subiu, 1UP, fase de chefe.
  void medium() {
    if (!_enabled) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastMedium < 150) return;
    _lastMedium = now;
    _fire(HapticFeedback.mediumImpact);
  }

  /// Momentos de impacto: dano, bomba, chefe abatido.
  void heavy() {
    if (!_enabled) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastHeavy < 200) return;
    _lastHeavy = now;
    _fire(HapticFeedback.heavyImpact);
  }

  /// Sem binding (testes headless) ou sem motor de vibração: silêncio.
  /// Feedback tátil jamais derruba o jogo.
  void _fire(Future<void> Function() impact) {
    try {
      impact().ignore();
    } catch (_) {}
  }
}

final haptics = Haptics.instance;
