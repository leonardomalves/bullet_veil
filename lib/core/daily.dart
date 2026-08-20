import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Desafio diário: MESMA seed para o dia inteiro (as mesmas ondas para todo
/// mundo), UMA tentativa. O gancho de "volta amanhã" mais barato do arcade.
class Daily extends ChangeNotifier {
  Daily._();

  static final Daily instance = Daily._();

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String dayKey(DateTime now) =>
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

  String get _day => dayKey(DateTime.now());

  /// Seed determinística do dia — vai direto para o Random do jogo.
  int get seed => int.parse(_day);

  bool get playedToday => _prefs?.containsKey('daily_$_day') ?? false;
  int get todayScore => _prefs?.getInt('daily_$_day') ?? 0;
  int get bestEver => _prefs?.getInt('daily_best') ?? 0;

  Future<void> record(int score) async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt('daily_$_day', score);
    if (score > bestEver) await p.setInt('daily_best', score);
    notifyListeners();
  }
}

final daily = Daily.instance;
