import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'garage.dart';

/// Condecorações persistentes. Dão metas de longo prazo além do recorde — e
/// agora PAGAM créditos: troféu que abastece o hangar traz de volta em dobro.
enum Achievement {
  firstBlood('Primeiro Sangue', 'Destrua sua primeira nave', 100),
  chain2('Em Cadeia', 'Alcance o multiplicador ×2', 150),
  chain4('Devastador', 'Alcance o multiplicador ×4', 400),
  wave10('Sobrevivente', 'Chegue à onda 10', 250),
  firstBoss('Caçador de Titãs', 'Derrote um chefe', 300),
  maxWeapon('Arsenal Total', 'Leve uma arma ao nível máximo', 300),
  graze100('Dança das Balas', 'Roce 100 balas numa partida', 400),
  fury('Fúria Encarnada', 'Encha o medidor de fúria', 350),
  allWeapons('Tríade', 'Use as três armas numa partida', 250),
  score50k('Ás', 'Faça 50 mil pontos', 400),
  score150k('Lenda Viva', 'Faça 150 mil pontos', 800),
  noMissBoss('Intocável', 'Derrote um chefe sem levar dano', 600);

  const Achievement(this.title, this.description, this.reward);

  final String title;
  final String description;

  /// Créditos pagos no desbloqueio.
  final int reward;
}

class Achievements extends ChangeNotifier {
  Achievements._();

  static final Achievements instance = Achievements._();

  SharedPreferences? _prefs;
  final Set<Achievement> _unlocked = {};

  /// Fila de recém-desbloqueados para o HUD exibir como "toast".
  final List<Achievement> pending = [];

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    for (final a in Achievement.values) {
      if (_prefs!.getBool('ach_${a.name}') ?? false) _unlocked.add(a);
    }
  }

  bool isUnlocked(Achievement a) => _unlocked.contains(a);
  int get unlockedCount => _unlocked.length;
  int get total => Achievement.values.length;

  /// Desbloqueia (se ainda não estava), paga a recompensa e enfileira o
  /// toast. Idempotente.
  void unlock(Achievement a) {
    if (_unlocked.add(a)) {
      _prefs?.setBool('ach_${a.name}', true);
      garage.addCredits(a.reward);
      pending.add(a);
      notifyListeners();
    }
  }

  Achievement? takePending() =>
      pending.isEmpty ? null : pending.removeAt(0);
}

final achievements = Achievements.instance;
