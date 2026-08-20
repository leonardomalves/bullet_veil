import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferências de jogo + progresso de desbloqueio que não é conquista.
class Settings extends ChangeNotifier {
  Settings._();

  static final Settings instance = Settings._();

  SharedPreferences? _prefs;

  /// Multiplicador do arrasto (dedo grande em tela pequena pede >1).
  static const sensitivities = [1.0, 1.5, 2.0];
  double _sensitivity = 1.0;

  bool _leftHanded = false;
  bool _legendUnlocked = false;
  bool _tutorialDone = false;

  double get sensitivity => _sensitivity;
  bool get leftHanded => _leftHanded;
  bool get legendUnlocked => _legendUnlocked;
  bool get tutorialDone => _tutorialDone;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _sensitivity = _prefs!.getDouble('set_sens') ?? 1.0;
    _leftHanded = _prefs!.getBool('set_left') ?? false;
    _legendUnlocked = _prefs!.getBool('set_legend') ?? false;
    _tutorialDone = _prefs!.getBool('set_tutorial') ?? false;
    notifyListeners();
  }

  /// Cicla 1x → 1.5x → 2x → 1x.
  void cycleSensitivity() {
    final i = sensitivities.indexOf(_sensitivity);
    _sensitivity = sensitivities[(i + 1) % sensitivities.length];
    _prefs?.setDouble('set_sens', _sensitivity);
    notifyListeners();
  }

  set leftHanded(bool v) {
    _leftHanded = v;
    _prefs?.setBool('set_left', v);
    notifyListeners();
  }

  /// LENDA abre quando o jogador derruba um chefe no VETERANO.
  void unlockLegend() {
    if (_legendUnlocked) return;
    _legendUnlocked = true;
    _prefs?.setBool('set_legend', true);
    notifyListeners();
  }

  void markTutorialDone() {
    if (_tutorialDone) return;
    _tutorialDone = true;
    _prefs?.setBool('set_tutorial', true);
    notifyListeners();
  }
}

final settings = Settings.instance;
