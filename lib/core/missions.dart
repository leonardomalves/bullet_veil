import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'garage.dart';

/// O que uma missão conta.
enum MissionGoal {
  kills,
  killsVulcan,
  killsLaser,
  killsMissile,
  graze,
  medals,
  wave,
  bombs,
  boss,
  score,
}

class MissionDef {
  const MissionDef(this.goal, this.target, this.reward, this._label);

  final MissionGoal goal;
  final int target;
  final int reward;
  final String _label;

  String get label => _label.replaceAll('#', '$target');
}

/// Pool fixo — o dia escolhe 3 deterministicamente. Metas de sessão curtas:
/// dão motivo de abrir o jogo HOJE além do recorde.
const _pool = <MissionDef>[
  MissionDef(MissionGoal.kills, 90, 300, 'Destrua # naves'),
  MissionDef(MissionGoal.killsVulcan, 45, 350, 'Destrua # naves com VULCAN'),
  MissionDef(MissionGoal.killsLaser, 40, 350, 'Destrua # naves com LASER'),
  MissionDef(MissionGoal.killsMissile, 35, 350, 'Destrua # naves com MÍSSEIS'),
  MissionDef(MissionGoal.graze, 60, 400, 'Roce # balas'),
  MissionDef(MissionGoal.medals, 30, 300, 'Colete # medalhas'),
  MissionDef(MissionGoal.wave, 12, 400, 'Chegue à onda #'),
  MissionDef(MissionGoal.bombs, 3, 250, 'Use # bombas'),
  MissionDef(MissionGoal.boss, 1, 500, 'Derrote # chefe'),
  MissionDef(MissionGoal.score, 30000, 450, 'Faça # pontos numa partida'),
];

class MissionState {
  MissionState(this.def);

  final MissionDef def;
  int progress = 0;
  bool paid = false;

  bool get done => progress >= def.target;
  double get fraction => (progress / def.target).clamp(0.0, 1.0);
}

/// Missões diárias: 3 por dia, escolhidas pela DATA (todo mundo — e todo boot —
/// vê as mesmas), pagando créditos na hora em que completam.
class Missions extends ChangeNotifier {
  Missions._();

  static final Missions instance = Missions._();

  SharedPreferences? _prefs;
  String _day = '';
  List<MissionState> today = [];

  /// Rótulos recém-completados para o HUD tostar.
  final List<String> pending = [];

  static String _dayKey(DateTime now) =>
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

  /// Sorteio determinístico: LCG semeado pela data → mesmos 3 índices o dia
  /// inteiro, sem repetir.
  static List<int> pickIndices(int seed, int poolSize, int count) {
    var s = seed;
    final picked = <int>[];
    while (picked.length < count) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      final i = s % poolSize;
      if (!picked.contains(i)) picked.add(i);
    }
    return picked;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _rollover(DateTime.now());
  }

  void _rollover(DateTime now) {
    final day = _dayKey(now);
    if (day == _day && today.isNotEmpty) return;
    _day = day;
    final indices = pickIndices(int.parse(day), _pool.length, 3);
    today = [for (final i in indices) MissionState(_pool[i])];
    for (var i = 0; i < today.length; i++) {
      today[i].progress = _prefs?.getInt('mis_${_day}_$i') ?? 0;
      today[i].paid = _prefs?.getBool('mis_${_day}_${i}_paid') ?? false;
    }
    notifyListeners();
  }

  /// Avança progresso. [value] substitui (para metas de "melhor valor", tipo
  /// onda alcançada/pontuação); senão soma [n].
  void track(MissionGoal goal, {int n = 1, int? value}) {
    _rollover(DateTime.now());
    var changed = false;
    for (var i = 0; i < today.length; i++) {
      final m = today[i];
      if (m.def.goal != goal || m.paid) continue;
      final before = m.progress;
      m.progress = value != null
          ? (value > m.progress ? value : m.progress)
          : m.progress + n;
      if (m.progress != before) changed = true;
      if (m.done && !m.paid) {
        m.paid = true;
        garage.addCredits(m.def.reward);
        pending.add('${m.def.label}  +${m.def.reward}¢');
        _prefs?.setBool('mis_${_day}_${i}_paid', true);
      }
    }
    if (changed) notifyListeners();
  }

  /// Persiste o progresso parcial (chamar no fim da partida).
  Future<void> flush() async {
    final p = _prefs;
    if (p == null) return;
    for (var i = 0; i < today.length; i++) {
      await p.setInt('mis_${_day}_$i', today[i].progress);
    }
  }

  String? takePending() => pending.isEmpty ? null : pending.removeAt(0);

  /// Zera o estado em memória (testes: singletons vazam entre casos).
  @visibleForTesting
  void debugReset() {
    _day = '';
    today = [];
    pending.clear();
  }
}

final missions = Missions.instance;
