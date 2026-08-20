import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estatísticas de carreira. Ver a própria curva subindo é retenção.
class Stats extends ChangeNotifier {
  Stats._();

  static final Stats instance = Stats._();

  SharedPreferences? _prefs;

  int totalKills = 0;
  int totalSeconds = 0;
  int totalRuns = 0;
  int bestWave = 0;

  /// Últimas 10 pontuações, mais recente por último — vira o sparkline.
  List<int> history = [];

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    totalKills = _prefs!.getInt('st_kills') ?? 0;
    totalSeconds = _prefs!.getInt('st_secs') ?? 0;
    totalRuns = _prefs!.getInt('st_runs') ?? 0;
    bestWave = _prefs!.getInt('st_wave') ?? 0;
    history = (_prefs!.getStringList('st_hist') ?? const [])
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    notifyListeners();
  }

  Future<void> recordRun({
    required int score,
    required int wave,
    required int kills,
    required int seconds,
  }) async {
    totalKills += kills;
    totalSeconds += seconds;
    totalRuns += 1;
    if (wave > bestWave) bestWave = wave;
    history.add(score);
    if (history.length > 10) history.removeAt(0);

    final p = _prefs;
    if (p != null) {
      await p.setInt('st_kills', totalKills);
      await p.setInt('st_secs', totalSeconds);
      await p.setInt('st_runs', totalRuns);
      await p.setInt('st_wave', bestWave);
      await p.setStringList('st_hist', history.map((e) => '$e').toList());
    }
    notifyListeners();
  }
}

final stats = Stats.instance;
