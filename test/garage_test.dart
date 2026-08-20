import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bullet_veil/core/garage.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('estado inicial: só a skin Aurora, sem módulos, zero créditos', () async {
    final g = Garage.instance;
    await g.load();
    expect(g.credits, 0);
    expect(g.ownsSkin(ShipSkin.aurora), isTrue);
    expect(g.ownsSkin(ShipSkin.gold), isFalse);
    expect(g.equipped, isEmpty);
    expect(g.skin, ShipSkin.aurora);
  });

  test('comprar exige crédito e debita', () async {
    final g = Garage.instance;
    await g.load();
    // Sem crédito não compra.
    expect(await g.buyModule(ShipModule.shield), isFalse);

    await g.addCredits(2000);
    expect(await g.buyModule(ShipModule.shield), isTrue);
    expect(g.credits, 2000 - ShipModule.shield.cost);
    expect(g.ownsModule(ShipModule.shield), isTrue);
    // Não compra de novo o que já tem.
    expect(await g.buyModule(ShipModule.shield), isFalse);
  });

  test('slots limitam módulos equipados', () async {
    final g = Garage.instance;
    await g.load();
    await g.addCredits(99999);
    await g.buyModule(ShipModule.shield);
    await g.buyModule(ShipModule.wingmen);
    await g.buyModule(ShipModule.overdrive);

    expect(await g.toggleModule(ShipModule.shield), isTrue);
    expect(await g.toggleModule(ShipModule.wingmen), isTrue);
    expect(g.equipped.length, kModuleSlots);
    // 3º não entra (slots cheios).
    expect(await g.toggleModule(ShipModule.overdrive), isFalse);
    expect(g.isEquipped(ShipModule.overdrive), isFalse);

    // Desequipa um e agora cabe.
    expect(await g.toggleModule(ShipModule.shield), isTrue); // desliga
    expect(await g.toggleModule(ShipModule.overdrive), isTrue);
    expect(g.isEquipped(ShipModule.overdrive), isTrue);
  });

  test('compra e loadout persistem entre cargas', () async {
    var g = Garage.instance;
    await g.load();
    await g.addCredits(5000);
    await g.buySkin(ShipSkin.gold);
    await g.equipSkin(ShipSkin.gold);
    await g.buyModule(ShipModule.missilePod);
    await g.toggleModule(ShipModule.missilePod);

    // Recarrega do "disco" (mesmo SharedPreferences mock).
    await g.load();
    expect(g.ownsSkin(ShipSkin.gold), isTrue);
    expect(g.skin, ShipSkin.gold);
    expect(g.ownsModule(ShipModule.missilePod), isTrue);
    expect(g.isEquipped(ShipModule.missilePod), isTrue);
  });

  test('créditos por pontuação', () {
    expect(Garage.creditsFor(0), 0);
    expect(Garage.creditsFor(4000), 200);
    expect(Garage.creditsFor(80000), 4000);
  });
}
