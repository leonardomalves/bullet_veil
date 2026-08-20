import 'package:shared_preferences/shared_preferences.dart';

import '../game/difficulty.dart';

/// Recorde por dificuldade. É o motor de rejogo do arcade: quatro recordes
/// separados são quatro montanhas para escalar, não uma.
class HighScores {
  HighScores._();

  static final HighScores instance = HighScores._();

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  int of(Difficulty d) => _prefs?.getInt('hs_${d.name}') ?? 0;

  /// Registra e retorna `true` se bateu o recorde anterior.
  Future<bool> record(Difficulty d, int score) async {
    if (score <= of(d)) return false;
    await _prefs?.setInt('hs_${d.name}', score);
    return true;
  }
}

final highScores = HighScores.instance;
