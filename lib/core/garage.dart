import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quantos módulos podem estar equipados ao mesmo tempo. O limite é o design:
/// obriga a escolher entre poder de fogo, defesa e utilidade — como montar a
/// nave nos jogos de referência. Um 3º slot pode ser comprado (caro): a meta
/// de longo prazo do hangar.
const int kModuleSlots = 2;
const int kMaxSlots = 3;
const int kThirdSlotCost = 6000;

/// Nível máximo de um módulo.
const int kMaxModuleLevel = 3;

/// Módulos (acessórios) da nave, comprados com créditos e equipados no hangar.
/// São a camada PERSISTENTE de loadout, diferente dos power-ups da partida.
enum ShipModule { missilePod, wingmen, shield, overdrive }

extension ShipModuleData on ShipModule {
  String get label => switch (this) {
        ShipModule.missilePod => 'LANÇA-MÍSSEIS',
        ShipModule.wingmen => 'ALAS (DRONES)',
        ShipModule.shield => 'ESCUDO',
        ShipModule.overdrive => 'OVERDRIVE',
      };

  String get description => switch (this) {
        ShipModule.missilePod => 'Dispara mísseis teleguiados sem parar',
        ShipModule.wingmen => 'Duas naves auxiliares atirando ao seu lado',
        ShipModule.shield => 'Absorve um dano e recarrega',
        ShipModule.overdrive => 'Cadência de tiro +33%',
      };

  // O ícone de cada módulo vive em `lib/ui/module_icon.dart`, desenhado em
  // vetor: os ícones do Material não têm identidade nenhuma numa loja de naves.

  int get cost => switch (this) {
        ShipModule.missilePod => 1200,
        ShipModule.wingmen => 1800,
        ShipModule.shield => 1500,
        ShipModule.overdrive => 900,
      };

  /// Custo de subir DE [level] para o próximo (I→II mais barato que II→III).
  int upgradeCost(int level) =>
      (cost * (level == 1 ? 0.9 : 1.6)).round();

  /// O que cada nível entrega — mostrado no hangar.
  String tierDesc(int level) => switch (this) {
        ShipModule.missilePod => const [
            'Mísseis a cada 1.0s',
            'Mísseis a cada 0.75s',
            'Mísseis a cada 0.55s',
          ][level - 1],
        ShipModule.wingmen => const [
            'Drones: dano 0.8',
            'Drones: dano 1.1',
            'Drones: dano 1.4',
          ][level - 1],
        ShipModule.shield => const [
            'Recarrega em 10s',
            'Recarrega em 7.5s',
            'Recarrega em 5.5s',
          ][level - 1],
        ShipModule.overdrive => const [
            'Cadência +33%',
            'Cadência +40%',
            'Cadência +46%',
          ][level - 1],
      };
}

/// Skins de casco — puramente cosméticas (cor do casco, contorno e núcleo).
/// ESPECTRO não se compra: destrava com a condecoração "Intocável".
enum ShipSkin { aurora, crimson, gold, voidfire, spectre }

extension ShipSkinData on ShipSkin {
  String get label => switch (this) {
        ShipSkin.aurora => 'AURORA',
        ShipSkin.crimson => 'CARMESIM',
        ShipSkin.gold => 'OURO',
        ShipSkin.voidfire => 'VAZIO',
        ShipSkin.spectre => 'ESPECTRO',
      };

  int get cost => switch (this) {
        ShipSkin.aurora => 0, // inicial, grátis
        ShipSkin.crimson => 800,
        ShipSkin.gold => 1500,
        ShipSkin.voidfire => 2500,
        ShipSkin.spectre => 0, // prêmio, não mercadoria
      };

  /// Skin-troféu: exige a condecoração "Intocável" para resgatar.
  bool get isTrophy => this == ShipSkin.spectre;

  Color get hull => switch (this) {
        ShipSkin.aurora => const Color(0xFFE8F4FF),
        ShipSkin.crimson => const Color(0xFFFFD7D7),
        ShipSkin.gold => const Color(0xFFFFF0C0),
        ShipSkin.voidfire => const Color(0xFFE7D6FF),
        ShipSkin.spectre => const Color(0xFFFFFFFF),
      };

  Color get accent => switch (this) {
        ShipSkin.aurora => const Color(0xFF35E1F5),
        ShipSkin.crimson => const Color(0xFFFF3B5C),
        ShipSkin.gold => const Color(0xFFFFC94A),
        ShipSkin.voidfire => const Color(0xFF9B4DFF),
        ShipSkin.spectre => const Color(0xFFB8FFF4),
      };

  Color get wing => switch (this) {
        ShipSkin.aurora => const Color(0xFF4C6BFF),
        ShipSkin.crimson => const Color(0xFF8E1B2E),
        ShipSkin.gold => const Color(0xFFE89B00),
        ShipSkin.voidfire => const Color(0xFF5A2E9E),
        ShipSkin.spectre => const Color(0xFF9FB6C4),
      };
}

/// Estado persistente do hangar: créditos, o que foi comprado e o que está
/// equipado.
class Garage extends ChangeNotifier {
  Garage._();
  static final Garage instance = Garage._();

  SharedPreferences? _prefs;

  int _credits = 0;
  final Set<ShipSkin> _ownedSkins = {ShipSkin.aurora};
  final Set<ShipModule> _ownedModules = {};
  final Map<ShipModule, int> _moduleLv = {};
  ShipSkin _skin = ShipSkin.aurora;
  final Set<ShipModule> _equipped = {};
  int _slots = kModuleSlots;

  int get credits => _credits;
  ShipSkin get skin => _skin;
  Set<ShipModule> get equipped => Set.unmodifiable(_equipped);

  /// Slots disponíveis (2 de fábrica, 3º comprável).
  int get slots => _slots;
  bool get hasThirdSlot => _slots >= kMaxSlots;

  bool ownsSkin(ShipSkin s) => _ownedSkins.contains(s);
  bool ownsModule(ShipModule m) => _ownedModules.contains(m);
  bool isEquipped(ShipModule m) => _equipped.contains(m);
  bool get slotsFull => _equipped.length >= _slots;

  /// Nível do módulo (1..3). Só faz sentido se ownsModule.
  int moduleLevel(ShipModule m) => _moduleLv[m] ?? 1;

  /// Loadout de níveis dos módulos EQUIPADOS — vai para dentro da partida.
  Map<ShipModule, int> get equippedLevels =>
      {for (final m in _equipped) m: moduleLevel(m)};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _credits = _prefs!.getInt('credits') ?? 0;
    _slots = _prefs!.getInt('slots') ?? kModuleSlots;
    _ownedSkins
      ..clear()
      ..add(ShipSkin.aurora);
    for (final s in ShipSkin.values) {
      if (_prefs!.getBool('skin_${s.name}') ?? false) _ownedSkins.add(s);
    }
    _ownedModules.clear();
    _moduleLv.clear();
    for (final m in ShipModule.values) {
      if (_prefs!.getBool('mod_${m.name}') ?? false) _ownedModules.add(m);
      final lv = _prefs!.getInt('modlv_${m.name}');
      if (lv != null) _moduleLv[m] = lv.clamp(1, kMaxModuleLevel);
    }
    final skinName = _prefs!.getString('equip_skin');
    _skin = ShipSkin.values.firstWhere(
      (s) => s.name == skinName && _ownedSkins.contains(s),
      orElse: () => ShipSkin.aurora,
    );
    _equipped.clear();
    for (final m in (_prefs!.getStringList('equip_mods') ?? const [])) {
      final mod = ShipModule.values.where((x) => x.name == m);
      if (mod.isNotEmpty && _ownedModules.contains(mod.first)) {
        _equipped.add(mod.first);
      }
    }
    notifyListeners();
  }

  Future<void> addCredits(int amount) async {
    if (amount <= 0) return;
    _credits += amount;
    await _prefs?.setInt('credits', _credits);
    notifyListeners();
  }

  /// Tenta comprar. Retorna false se faltar crédito ou já tiver.
  Future<bool> buySkin(ShipSkin s) async {
    if (_ownedSkins.contains(s) || _credits < s.cost) return false;
    _credits -= s.cost;
    _ownedSkins.add(s);
    await _prefs?.setInt('credits', _credits);
    await _prefs?.setBool('skin_${s.name}', true);
    notifyListeners();
    return true;
  }

  Future<bool> buyModule(ShipModule m) async {
    if (_ownedModules.contains(m) || _credits < m.cost) return false;
    _credits -= m.cost;
    _ownedModules.add(m);
    _moduleLv[m] = 1;
    await _prefs?.setInt('credits', _credits);
    await _prefs?.setBool('mod_${m.name}', true);
    await _prefs?.setInt('modlv_${m.name}', 1);
    notifyListeners();
    return true;
  }

  /// Sobe o módulo um nível (I→II→III). Falha sem crédito/sem posse/no teto.
  Future<bool> upgradeModule(ShipModule m) async {
    if (!_ownedModules.contains(m)) return false;
    final lv = moduleLevel(m);
    if (lv >= kMaxModuleLevel) return false;
    final cost = m.upgradeCost(lv);
    if (_credits < cost) return false;
    _credits -= cost;
    _moduleLv[m] = lv + 1;
    await _prefs?.setInt('credits', _credits);
    await _prefs?.setInt('modlv_${m.name}', lv + 1);
    notifyListeners();
    return true;
  }

  /// Compra o 3º slot — o objetivo caro de longo prazo do hangar.
  Future<bool> buyThirdSlot() async {
    if (hasThirdSlot || _credits < kThirdSlotCost) return false;
    _credits -= kThirdSlotCost;
    _slots = kMaxSlots;
    await _prefs?.setInt('credits', _credits);
    await _prefs?.setInt('slots', _slots);
    notifyListeners();
    return true;
  }

  Future<void> equipSkin(ShipSkin s) async {
    if (!_ownedSkins.contains(s)) return;
    _skin = s;
    await _prefs?.setString('equip_skin', s.name);
    notifyListeners();
  }

  /// Liga/desliga um módulo. Ao ligar com os slots cheios, não faz nada
  /// (o jogador precisa desequipar algo antes) e retorna false.
  Future<bool> toggleModule(ShipModule m) async {
    if (!_ownedModules.contains(m)) return false;
    if (_equipped.contains(m)) {
      _equipped.remove(m);
    } else {
      if (_equipped.length >= _slots) return false;
      _equipped.add(m);
    }
    await _prefs?.setStringList(
      'equip_mods',
      _equipped.map((e) => e.name).toList(),
    );
    notifyListeners();
    return true;
  }

  /// Créditos ganhos numa partida a partir da pontuação.
  ///
  /// O divisor acompanha a escala do placar. A queda NÃO foi uniforme: medida
  /// em partida simulada, a pontuação caiu 38% no PILOTO e 21% no LENDA, e a
  /// colheita de medalha de um chefe caiu 4× (1,12M → 280k). O 40 antigo virou
  /// 20 para o ganho por partida ficar perto do que era — senão o hangar
  /// viraria moagem. Vale reconferir depois de algumas partidas de verdade.
  static int creditsFor(int score) => (score / 20).round();
}

final garage = Garage.instance;
