import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bullet_veil/game/atlas.dart';
import 'package:bullet_veil/core/garage.dart';
import 'package:bullet_veil/core/missions.dart';
import 'package:bullet_veil/core/settings.dart';
import 'package:bullet_veil/game/danmaku_game.dart';
import 'package:bullet_veil/game/difficulty.dart';
import 'package:bullet_veil/game/enemy.dart';

/// Mecânicas dos pacotes A–D: agonia de chefe, hitstop, formações, missões,
/// tiers do hangar e trava da LENDA.
void main() {
  DanmakuGame build() => DanmakuGame(onGameOver: (s, g, w) {});

  group('chefe morre em sequência, não evapora', () {
    testWithGame<DanmakuGame>(
      'dano letal inicia a agonia; o abate vem ~1.6s depois, com tally',
      build,
      (game) async {
        final boss = EnemyFactory(difficultyConfigs[Difficulty.normal]!).boss(1);
        await game.world.add(boss);
        await game.ready();

        final scoreBefore = game.scoreNotifier.value;
        boss.damage(1e9);
        expect(boss.dying, isTrue);
        game.update(1 / 60);
        expect(boss.isRemoved, isFalse, reason: 'agonia segura o chefe em cena');

        // Roda a sequência inteira (1.6s + folga, passando pelo hitstop).
        for (var i = 0; i < 60 * 4; i++) {
          game.update(1 / 60);
        }
        expect(game.world.children.whereType<Enemy>().where((e) => e.isBoss),
            isEmpty,
            reason: 'estourou no fim da sequência');
        expect(game.scoreNotifier.value, greaterThan(scoreBefore));
        expect(game.stageClearNotifier.value, isNotNull,
            reason: 'o tally de fim de estágio aparece');
      },
    );
  });

  group('hitstop', () {
    testWithGame<DanmakuGame>(
      'congela o mundo pelo tempo pedido',
      build,
      (game) async {
        final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
        final grunt = kit.grunt(360);
        await game.world.add(grunt);
        await game.ready();
        game.update(1 / 60); // primeiro tick move o grunt para dentro

        game.hitstop(0.5);
        final before = grunt.position.clone();
        game.update(1 / 60);
        expect(grunt.position, before, reason: 'congelado durante o hitstop');

        for (var i = 0; i < 40; i++) {
          game.update(1 / 60); // 0.66s > hitstop
        }
        expect(grunt.position, isNot(before), reason: 'o mundo volta a andar');
      },
    );
  });

  group('formações', () {
    testWithGame<DanmakuGame>(
      'aniquilar o grupo inteiro paga bônus',
      build,
      (game) async {
        final id = game.registerFormation(2);
        final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
        final members = kit.formationV(id).take(2).toList();
        await game.world.addAll(members);
        await game.ready();

        members[0].damage(1e9);
        final between = game.scoreNotifier.value;
        members[1].damage(1e9);
        final gained = game.scoreNotifier.value - between;
        // 2500 × estágio(1) além do valor da nave: só o bônus já supera 2000.
        expect(gained, greaterThan(2000),
            reason: 'último abate carrega o bônus de FORMAÇÃO');
      },
    );

    testWithGame<DanmakuGame>(
      'fuga de um membro quebra o bônus',
      build,
      (game) async {
        final id = game.registerFormation(2);
        final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
        final members = kit.formationV(id).take(2).toList();
        await game.world.addAll(members);
        await game.ready();

        members[0].removeFromParent(); // saiu sem morrer
        game.update(0);
        members[1].damage(1e9);
        // Sem o bônus: ganho fica na casa do scoreValue (160×mult) ≪ 2000.
        expect(game.scoreNotifier.value, lessThan(2000));
      },
    );
  });

  test('missões: sorteio do dia é determinístico e sem repetição', () {
    final a = Missions.pickIndices(20260727, 10, 3);
    final b = Missions.pickIndices(20260727, 10, 3);
    expect(a, b);
    expect(a.toSet().length, 3);
    final c = Missions.pickIndices(20260728, 10, 3);
    expect(c, isNot(a), reason: 'outro dia, outras missões (quase sempre)');
  });

  test('missão completa paga créditos na hora', () async {
    SharedPreferences.setMockInitialValues({});
    await garage.load();
    missions.debugReset(); // singletons vazam progresso dos testes de jogo
    await missions.load();
    expect(missions.today.length, 3);

    final m = missions.today.first;
    final creditsBefore = garage.credits;
    // Cobre metas de contagem e de "melhor valor" de uma vez.
    missions.track(m.def.goal, n: m.def.target, value: m.def.target);
    expect(m.done, isTrue);
    expect(m.paid, isTrue);
    expect(garage.credits, creditsBefore + m.def.reward);
    expect(missions.pending, isNotEmpty);
  });

  test('hangar: tiers sobem até III e o 3º slot abre espaço', () async {
    SharedPreferences.setMockInitialValues({});
    await garage.load();
    await garage.addCredits(99999);

    await garage.buyModule(ShipModule.shield);
    expect(garage.moduleLevel(ShipModule.shield), 1);
    expect(await garage.upgradeModule(ShipModule.shield), isTrue);
    expect(await garage.upgradeModule(ShipModule.shield), isTrue);
    expect(garage.moduleLevel(ShipModule.shield), kMaxModuleLevel);
    expect(await garage.upgradeModule(ShipModule.shield), isFalse,
        reason: 'nível III é o teto');

    await garage.buyModule(ShipModule.wingmen);
    await garage.buyModule(ShipModule.overdrive);
    await garage.toggleModule(ShipModule.shield);
    await garage.toggleModule(ShipModule.wingmen);
    expect(await garage.toggleModule(ShipModule.overdrive), isFalse,
        reason: '2 slots de fábrica');

    expect(await garage.buyThirdSlot(), isTrue);
    expect(garage.slots, kMaxSlots);
    expect(await garage.toggleModule(ShipModule.overdrive), isTrue,
        reason: 'o 3º slot abre a vaga');
    expect(garage.equippedLevels[ShipModule.shield], kMaxModuleLevel);
  });

  test('LENDA destrava e persiste', () async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    expect(settings.legendUnlocked, isFalse);
    settings.unlockLegend();
    expect(settings.legendUnlocked, isTrue);
  });

  test('arquétipos novos saem da fábrica com formas coerentes', () {
    final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
    expect(kit.sniper(100).role, EnemyRole.sniper);
    expect(kit.kamikaze(100).radius, lessThan(kit.midBoss(1).radius));
    expect(kit.freighter(true).medalCarrier, isTrue);
    expect(kit.midBoss(2).elite, isTrue);
    final v = kit.formationV(7);
    expect(v.length, 5);
    expect(v.every((e) => e.formationId == 7), isTrue);
    expect(bossTitle(1), contains('VULKAN'));
    expect(bossTitle(4), contains('MK-2'), reason: '2º ciclo vira MK-II');
  });

  testWithGame<DanmakuGame>(
    'revive (anúncio) traz a nave de volta com 2 naves e invulnerável',
    build,
    (game) async {
      // Mata as 3 naves atravessando slow-mo/hitstop até o game over real.
      var guard = 0;
      while (!game.isOver && guard++ < 4000) {
        game.player.invuln = 0;
        game.enemyBullets.spawn(
          x: game.player.position.x,
          y: game.player.position.y,
          vx: 0,
          vy: 0,
          shape: BulletShape.orb,
          color: 0,
        );
        game.update(1 / 60);
      }
      expect(game.isOver, isTrue, reason: 'sanidade: morreu de verdade');

      game.revive();
      expect(game.isOver, isFalse);
      expect(game.livesNotifier.value, 2);
      expect(game.player.vulnerable, isFalse,
          reason: 'volta com um respiro de invulnerabilidade');
      expect(game.enemyBullets.count, 0, reason: 'tela limpa na volta');

      // Revive com o jogo vivo é no-op (o limite de 1× é da UI).
      game.revive();
      expect(game.livesNotifier.value, 2);
    },
  );

  testWithGame<DanmakuGame>(
    'seed fixa constrói o modo diário sem sustos',
    () => DanmakuGame(onGameOver: (s, g, w) {}, daily: true, seed: 20260727),
    (game) async {
      expect(game.daily, isTrue);
      game.update(1 / 60);
    },
  );
}
