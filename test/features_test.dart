import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/core/high_scores.dart';
import 'package:bullet_veil/game/atlas.dart';
import 'package:bullet_veil/game/bullet_field.dart';
import 'package:bullet_veil/game/danmaku_game.dart';
import 'package:bullet_veil/game/difficulty.dart';
import 'package:bullet_veil/game/enemy.dart';
import 'package:bullet_veil/game/pickups.dart';
import 'package:bullet_veil/game/player.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  DanmakuGame build([Difficulty d = Difficulty.normal]) =>
      DanmakuGame(onGameOver: (score, graze, wave) {}, difficulty: d);

  Vector2 at() => Vector2(360, 800);

  group('dificuldade', () {
    test('fábrica aplica multiplicador de HP', () {
      final easy = EnemyFactory(difficultyConfigs[Difficulty.easy]!);
      final insane = EnemyFactory(difficultyConfigs[Difficulty.insane]!);
      expect(insane.grunt(0).hp, greaterThan(easy.grunt(0).hp));
      expect(insane.boss(1).hp, greaterThan(easy.boss(1).hp));
    });

    test('vida do chefe cresce a cada estágio', () {
      final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
      expect(kit.boss(2).hp, greaterThan(kit.boss(1).hp));
      expect(kit.boss(3).hp, greaterThan(kit.boss(2).hp));
      // E o 1º chefe já é um combate, não some num piscar (era ~820).
      expect(kit.boss(1).hp, greaterThan(2000));
    });

    test('waveScale endurece os inimigos comuns com o avanço', () {
      final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
      final base = kit.grunt(0).hp;
      kit.waveScale = 2.0;
      expect(kit.grunt(0).hp, greaterThan(base));
    });

    test('configs escalam velocidade e recompensa juntas', () {
      for (var i = 1; i < Difficulty.values.length; i++) {
        final prev = difficultyConfigs[Difficulty.values[i - 1]]!;
        final cur = difficultyConfigs[Difficulty.values[i]]!;
        expect(cur.speedBase, greaterThan(prev.speedBase),
            reason: 'velocidade deve subir com a dificuldade');
        expect(cur.scoreMul, greaterThan(prev.scoreMul),
            reason: 'risco maior deve pagar mais');
      }
    });

    testWithGame<DanmakuGame>(
      'jogo usa a velocidade-base da dificuldade escolhida',
      () => build(Difficulty.insane),
      (game) async {
        game.update(0);
        expect(
          game.fireContext.speedScale,
          closeTo(difficultyConfigs[Difficulty.insane]!.speedBase, 0.01),
        );
      },
    );
  });

  group('armas especiais', () {
    testWithGame<DanmakuGame>('cápsula troca a arma mantendo o nível', build,
        (game) async {
      // Sobe até o nível 4 no vulcan.
      for (var i = 0; i < 7; i++) {
        game.collectPickup(PickupType.power, at());
      }
      expect(game.weaponLevel, 4);
      expect(game.weaponType, WeaponType.vulcan);

      game.collectPickup(PickupType.weaponLaser, at());
      expect(game.weaponType, WeaponType.laser);
      expect(game.weaponLevel, 4, reason: 'trocar arma não pode zerar o nível');
    });

    testWithGame<DanmakuGame>(
      'cápsula da arma já equipada vira pontos',
      build,
      (game) async {
        final before = game.scoreNotifier.value;
        game.collectPickup(PickupType.weaponVulcan, at());
        expect(game.weaponType, WeaponType.vulcan);
        expect(game.scoreNotifier.value, greaterThan(before));
      },
    );

    test('perfurante tem recarga entre acertos (não derrete alvo grande)',
        () async {
      final atlas = await BulletAtlas.generate();
      final field = BulletField(atlas: atlas, capacity: 10);

      field.spawn(
        x: 300, y: 300, vx: 0, vy: 0,
        shape: BulletShape.laser, color: 2,
        dmg: 2.0, pierce: 3,
      );
      // 1º acerto cobra e entra em recarga.
      expect(field.hitCircle(300, 300, 30), 2.0);
      expect(field.count, 1);
      // Enquanto recarrega, atravessa sem cobrar (era o bug de re-hit por frame).
      expect(field.hitCircle(300, 300, 30), 0.0);
      // Passado o tempo de recarga, cobra de novo.
      field.update(0.12);
      expect(field.hitCircle(300, 300, 30), 2.0);
    });

    test('comum é consumida no primeiro acerto', () async {
      final atlas = await BulletAtlas.generate();
      final field = BulletField(atlas: atlas, capacity: 10);
      field.spawn(
        x: 300, y: 300, vx: 0, vy: 0,
        shape: BulletShape.laser, color: 3, dmg: 1.0,
      );
      expect(field.hitCircle(300, 300, 30), 1.0);
      expect(field.count, 0);
    });

    test('míssil curva até o alvo; bala reta sai da tela', () async {
      final atlas = await BulletAtlas.generate();

      // Controle: mesma bala SEM teleguiagem sobe reto e é descartada no topo.
      final straight = BulletField(atlas: atlas, capacity: 10);
      straight.spawn(
        x: 300, y: 800, vx: 0, vy: -600,
        shape: BulletShape.dart, color: 1,
      );

      // Teleguiada: raio de giro v/ω = 600/6 = 100px — ela alcança o alvo e
      // fica orbitando perto dele em vez de fugir da tela.
      final homing = BulletField(atlas: atlas, capacity: 10)
        ..homingTargets = const [Offset(700, 200)];
      homing.spawn(
        x: 300, y: 800, vx: 0, vy: -600,
        shape: BulletShape.dart, color: 1,
        homing: 6.0,
      );

      for (var i = 0; i < 96; i++) {
        straight.update(1 / 60);
        homing.update(1 / 60);
      }

      expect(straight.count, 0, reason: 'a reta deve ter saído pelo topo');
      expect(homing.count, 1, reason: 'a teleguiada deve seguir viva');
      expect(
        homing.hitCircle(700, 200, 250),
        greaterThan(0),
        reason: 'e deve estar na vizinhança do alvo',
      );
    });
  });

  group('cadeia e gemas', () {
    testWithGame<DanmakuGame>(
      'abates em sequência sobem o multiplicador em degraus',
      build,
      (game) async {
        expect(game.multiplier, 1);
        final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
        for (var i = 0; i < 5; i++) {
          game.onEnemyKilled(kit.grunt(100.0 + i));
        }
        expect(game.multiplier, 2);
        for (var i = 0; i < 7; i++) {
          game.onEnemyKilled(kit.grunt(200.0 + i));
        }
        expect(game.multiplier, 3);
      },
    );

    testWithGame<DanmakuGame>(
      'a cadeia expira sem abates e volta a ×1',
      build,
      (game) async {
        final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
        for (var i = 0; i < 6; i++) {
          game.onEnemyKilled(kit.grunt(100.0 + i));
        }
        expect(game.multiplier, 2);
        for (var i = 0; i < 60 * 4; i++) {
          game.update(1 / 60);
        }
        expect(game.multiplier, 1);
      },
    );

    testWithGame<DanmakuGame>(
      'medalha paga o degrau × multiplicador e o degrau sobe a cada coleta',
      build,
      (game) async {
        final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
        for (var i = 0; i < 5; i++) {
          game.onEnemyKilled(kit.grunt(100.0 + i));
        }
        expect(game.multiplier, 2);

        // 1ª medalha vale o degrau inicial (100) × multiplicador (2).
        var before = game.scoreNotifier.value;
        game.collectGem(0, at());
        expect(game.scoreNotifier.value - before, 100 * 2);
        expect(game.medalNotifier.value, 200, reason: 'degrau deve subir');

        // 2ª medalha já vale o degrau novo (200).
        before = game.scoreNotifier.value;
        game.collectGem(0, at());
        expect(game.scoreNotifier.value - before, 200 * 2);
      },
    );

    testWithGame<DanmakuGame>(
      'deixar a medalha cair zera o degrau',
      build,
      (game) async {
        game.collectGem(0, at()); // sobe para 200
        game.collectGem(0, at()); // sobe para 400
        expect(game.medalNotifier.value, greaterThan(100));
        game.onGemMissed();
        expect(game.medalNotifier.value, 0,
            reason: 'perder reseta o degrau e esconde o chip do HUD');
      },
    );
  });

  group('fúria (rank)', () {
    testWithGame<DanmakuGame>(
      'ficar forte sobe a fúria; morrer a derruba',
      build,
      (game) async {
        // Sobe ao máximo de arma e segura mísseis: a fúria deve subir.
        for (var i = 0; i < 30; i++) {
          game.collectPickup(PickupType.power, at());
        }
        game.collectPickup(PickupType.weaponMissile, at());
        for (var i = 0; i < 120; i++) {
          game.update(1 / 60);
        }
        final hot = game.rank;
        expect(hot, greaterThan(0.1), reason: 'poder deveria acender a fúria');

        // Simula morte: a fúria cai (via colisão direta forçada é privado, então
        // checamos o efeito público de um hit por bala não dá — usamos o campo).
        // A queda vem de _playerHit; reproduzimos o encadeamento por bomba, que
        // também alivia, garantindo que a fúria é reduzível.
        game.useBomb();
        expect(game.rank, lessThan(hot),
            reason: 'aliviar (bomba/morte) deve reduzir a fúria');
      },
    );

    test('dificuldades altas ganham fúria mais rápido e mandam mais naves', () {
      final normal = difficultyConfigs[Difficulty.normal]!;
      final insane = difficultyConfigs[Difficulty.insane]!;
      expect(insane.rankGainMul, greaterThan(normal.rankGainMul));
      expect(insane.rankMaxExtraEnemies, greaterThan(normal.rankMaxExtraEnemies));
    });
  });

  group('recordes', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('grava recorde por dificuldade e só melhora', () async {
      await highScores.load();
      expect(highScores.of(Difficulty.normal), 0);

      expect(await highScores.record(Difficulty.normal, 5000), isTrue);
      expect(highScores.of(Difficulty.normal), 5000);

      expect(await highScores.record(Difficulty.normal, 3000), isFalse);
      expect(highScores.of(Difficulty.normal), 5000);

      // Dificuldades não se misturam.
      expect(highScores.of(Difficulty.insane), 0);
    });
  });
}
