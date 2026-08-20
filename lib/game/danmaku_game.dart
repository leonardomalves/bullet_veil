import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../core/achievements.dart';
import '../core/garage.dart';
import '../core/haptics.dart';
import '../core/missions.dart';
import '../core/replay.dart';
import '../core/settings.dart';
import '../core/sfx.dart';
import 'arena.dart';
import 'atlas.dart';
import 'brain.dart';
import 'bullet_field.dart';
import 'difficulty.dart';
import 'effects.dart';
import 'enemy.dart';
import 'patterns.dart';
import 'pickups.dart';
import 'player.dart';

/// Captura o arraste e move a nave em delta relativo.
class ControlLayer extends PositionComponent
    with DragCallbacks, HasGameReference<DanmakuGame> {
  ControlLayer()
      : super(size: Vector2(kArenaWidth, kArenaHeight), priority: 30);

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (game.paused) return; // pausado: nave não anda "por fora" do loop
    final d = event.localDelta * settings.sensitivity;
    game.player.moveBy(d);
    game.movedNotifier.value += d.length; // combustível do tutorial
  }
}

class DanmakuGame extends FlameGame {
  DanmakuGame({
    required this.onGameOver,
    this.difficulty = Difficulty.normal,
    this.skin = ShipSkin.aurora,
    this.modules = const {},
    this.moduleLevels = const {},
    this.daily = false,
    int? seed,
  })  : _seed = seed,
        _rng = seed != null ? math.Random(seed) : math.Random(),
        super(
          camera: CameraComponent.withFixedResolution(
            width: kArenaWidth,
            height: kArenaHeight,
          ),
        );

  final void Function(int score, int graze, int wave) onGameOver;
  final Difficulty difficulty;

  /// Loadout escolhido no hangar.
  final ShipSkin skin;
  final Set<ShipModule> modules;

  /// Nível (I..III) de cada módulo equipado.
  final Map<ShipModule, int> moduleLevels;

  /// Desafio diário: seed fixa da data, 1 tentativa.
  final bool daily;

  final int? _seed;

  /// Replay do diário (formato v1) — evidência para o leaderboard online.
  ReplayRecorder? recorder;

  int moduleLv(ShipModule m) => (moduleLevels[m] ?? 1).clamp(1, kMaxModuleLevel);

  bool get hasMissilePod => modules.contains(ShipModule.missilePod);
  bool get hasWingmen => modules.contains(ShipModule.wingmen);
  bool get hasShield => modules.contains(ShipModule.shield);
  bool get hasOverdrive => modules.contains(ShipModule.overdrive);

  DifficultyConfig get cfg => difficultyConfigs[difficulty]!;

  static const double _playerBulletDamage = 3;

  final scoreNotifier = ValueNotifier(0);
  final livesNotifier = ValueNotifier(kStartLives);
  final bombsNotifier = ValueNotifier(2);
  final grazeNotifier = ValueNotifier(0);
  final bulletsNotifier = ValueNotifier(0);
  final fpsNotifier = ValueNotifier(60.0);
  final waveNotifier = ValueNotifier(0);
  final stageNotifier = ValueNotifier(1);
  final bossHpNotifier = ValueNotifier<double?>(null);

  final weaponLevelNotifier = ValueNotifier(1);
  final powerFillNotifier = ValueNotifier(0.0);
  final weaponTypeNotifier = ValueNotifier(WeaponType.vulcan);

  final multiplierNotifier = ValueNotifier(1);
  final chainFillNotifier = ValueNotifier(0.0);

  /// Fúria (rank): 0..1. A alavanca de dificuldade dinâmica.
  final rankNotifier = ValueNotifier(0.0);

  /// Cadeia de medalhas: valor por medalha, sobe coletando em sequência.
  final medalNotifier = ValueNotifier(0);

  /// Escudo do módulo: pronto (absorve) ou recarregando.
  final shieldNotifier = ValueNotifier(false);

  /// Nome do chefe em cena (para o HUD apresentar).
  final bossNameNotifier = ValueNotifier<String?>(null);

  /// Tally de fim de estágio (null = sem tally na tela).
  final stageClearNotifier =
      ValueNotifier<({int stage, int noMiss, int graze, int medal})?>(null);

  /// Distância total arrastada — o tutorial usa para saber que o jogador
  /// aprendeu a mover.
  final movedNotifier = ValueNotifier(0.0);

  late final BulletAtlas atlas;
  late final BulletField enemyBullets;
  late final BulletField playerBullets;
  late final SparkField sparks;
  late final Starfield starfield;
  late final Player player;
  late final FireContext fireContext;
  late final EnemyFactory kit = EnemyFactory(cfg);

  final math.Random _rng;

  /// Cérebro de ameaça: aprende velocidade e hábitos do jogador; a Fúria é a
  /// agressividade da mira. Usa o MESMO Random do jogo (diário determinístico).
  late final ThreatBrain brain = ThreatBrain(_rng);
  double _shake = 0;
  double _waveCd = 2.8;
  int _wave = 0;
  int _stage = 1;
  double _fps = 60;
  bool _over = false;

  // Tempo dramático: hitstop congela, slow-mo estica a morte.
  double _hitstop = 0;
  double _slowmo = 0;

  /// Estatísticas da partida (alimentam a página de stats no fim).
  int killsThisRun = 0;
  double elapsedSeconds = 0;

  // Formações: id → quantos ainda vivos. Zerar TODOS paga bônus.
  final Map<int, int> _formations = {};
  int _formationSeq = 0;
  int _grazeAtStage = 0;

  int _weaponLevel = 1;
  double _powerFill = 0;
  int _killsSinceDrop = 0;
  int _killsSinceWeapon = 0;
  late int _nextOneUp = cfg.oneUpEvery;
  double _difficultyT = 0;

  static const _chainWindow = 3.0;
  int _chainKills = 0;
  double _chainTimer = 0;

  // Módulos do hangar
  double _podCd = 0;
  bool _shieldUp = false;
  double _shieldCd = 0;

  // Fúria / rank
  double _rank = 0;
  double _musicCd = 0; // cadência de atualização da camada de intensidade

  // Cadeia de medalhas
  int _medalIndex = 0;

  // Achievements dentro da partida
  final Set<WeaponType> _usedWeapons = {WeaponType.vulcan};
  bool _bossAlive = false;
  bool _bossHitTaken = false;

  int get weaponLevel => _weaponLevel;
  WeaponType get weaponType => weaponTypeNotifier.value;
  double get rank => _rank;
  bool get isOver => _over;

  int get multiplier => _chainKills >= 20
      ? 4
      : _chainKills >= 12
          ? 3
          : _chainKills >= 5
              ? 2
              : 1;

  int get _medalValue => kMedalSteps[_medalIndex.clamp(0, kMedalSteps.length - 1)];

  /// Naves extras por onda que a fúria manda para cima do jogador forte —
  /// o "quando estou com míssil, vem mais inimigo".
  int get _extraEnemies => (_rank * cfg.rankMaxExtraEnemies).floor();

  /// Pan estéreo pela posição horizontal — o espaço sonoro segue a tela.
  double _pan(double x) => (x / kArenaWidth * 2 - 1) * 0.7;

  @override
  Color backgroundColor() => const Color(0xFF05030F);

  @override
  Future<void> onLoad() async {
    camera.viewfinder.position = Vector2(kArenaWidth / 2, kArenaHeight / 2);
    bombsNotifier.value = cfg.startBombs;

    atlas = await BulletAtlas.generate();
    enemyBullets = BulletField(
      atlas: atlas,
      capacity: kEnemyBulletCap,
      additive: false,
    )..priority = 10;
    playerBullets = BulletField(atlas: atlas, capacity: kPlayerBulletCap)
      ..priority = 6;
    sparks = SparkField(atlas: atlas);
    starfield = Starfield();
    player = Player(
      skin: skin,
      wingmen: hasWingmen,
      // OVERDRIVE por nível: I -33%, II -40%, III -46% de intervalo.
      fireRateMul: hasOverdrive
          ? const [0.67, 0.60, 0.54][
              (moduleLevels[ShipModule.overdrive] ?? 1).clamp(1, 3) - 1]
          : 1.0,
      wingmenDamage: const [0.8, 1.1, 1.4][
          (moduleLevels[ShipModule.wingmen] ?? 1).clamp(1, 3) - 1],
    );
    fireContext = FireContext(enemyBullets);
    fireContext.speedScale = cfg.speedBase;
    fireContext.brain = brain;

    _shieldUp = hasShield;
    shieldNotifier.value = _shieldUp;

    if (daily) {
      recorder = ReplayRecorder(
        seed: _seed ?? 0,
        mode: 'daily',
        clientVersion: kClientVersion,
      );
    }

    await world.addAll([
      starfield,
      playerBullets,
      enemyBullets,
      sparks,
      player,
      ControlLayer(),
    ]);
  }

  // ── Loop ───────────────────────────────────────────────────────────────

  /// Congela o mundo por [s] segundos (o maior pedido vence).
  void hitstop(double s) => _hitstop = math.max(_hitstop, s);

  @override
  void update(double dt) {
    // Tempo dramático: hitstop zera o dt do mundo; slow-mo o estica.
    var eff = dt;
    if (_hitstop > 0) {
      _hitstop -= dt;
      eff = 0;
    } else if (_slowmo > 0) {
      _slowmo -= dt;
      eff = dt * 0.28;
    }
    camera.viewfinder.zoom =
        1 + (_slowmo > 0 ? 0.07 * (_slowmo / 0.55).clamp(0.0, 1.0) : 0.0);

    if (!_over) {
      playerBullets.homingTargets = [
        for (final e in world.children.whereType<Enemy>())
          Offset(e.position.x, e.position.y),
      ];
    }

    super.update(eff);
    if (dt > 0) _fps = _fps * 0.9 + (1 / dt) * 0.1;
    fpsNotifier.value = _fps;

    if (_over) return;
    elapsedSeconds += dt;
    // A trajetória entra na régua de 20 Hz em tempo de JOGO (eff).
    recorder?.sample(eff, player.position.x, player.position.y);

    // O cérebro observa o jogador; a Fúria dita o quão esperta é a mira.
    brain
      ..aggression = _rank
      ..observe(eff, player.position);

    _tickRank(eff);
    _difficultyT = math.min(1.0, _wave / cfg.rampWaves);
    fireContext.speedScale = cfg.speedBase +
        (cfg.speedMax - cfg.speedBase) * _difficultyT +
        cfg.rankSpeedBonus * _rank;

    _tickChain(eff);
    _tickModules(eff);
    _tickWaves(eff);
    if (eff > 0) _collide();
    _applyShake(dt); // shake corre em tempo real: treme até no freeze-frame
    _checkScoreMilestones();

    // A camada rítmica da música acompanha a FÚRIA.
    _musicCd -= dt;
    if (_musicCd <= 0) {
      _musicCd = 0.3;
      sfx.setIntensity(_rank);
    }

    bulletsNotifier.value = enemyBullets.count + playerBullets.count;

    final boss = world.children.whereType<Enemy>().where((e) => e.isBoss);
    bossHpNotifier.value = boss.isEmpty ? null : boss.first.hpFraction;
  }

  /// Efeitos por frame dos módulos do hangar.
  void _tickModules(double dt) {
    if (hasMissilePod) {
      _podCd -= dt;
      if (_podCd <= 0) {
        // Cadência do pod por nível: 1.0s / 0.75s / 0.55s.
        _podCd = const [1.0, 0.75, 0.55][moduleLv(ShipModule.missilePod) - 1];
        // Dois mísseis teleguiados independentes da arma principal.
        for (final s in [-1.0, 1.0]) {
          playerBullets.spawn(
            x: player.position.x + s * 16,
            y: player.position.y,
            vx: s * 260,
            vy: -360,
            shape: BulletShape.dart,
            color: 7,
            scale: 0.7,
            dmg: 1.2,
            homing: 5.0,
          );
        }
      }
    }
    if (hasShield && !_shieldUp) {
      _shieldCd -= dt;
      if (_shieldCd <= 0) {
        _shieldUp = true;
        shieldNotifier.value = true;
      }
    }
  }

  /// Recarga do escudo por nível: 10s / 7.5s / 5.5s.
  double get _shieldRechargeS =>
      const [10.0, 7.5, 5.5][moduleLv(ShipModule.shield) - 1];

  /// A fúria sobe com poder e agressão, desce quando o jogador está fraco.
  /// É o motor que faz o jogo empurrar de volta contra quem domina.
  void _tickRank(double dt) {
    var gain = 0.010; // atirar (autofire sempre ligado)
    if (weaponType == WeaponType.missile) {
      // Segurar os mísseis teleguiados é a jogada mais forte — então é a que
      // mais provoca o jogo. Exatamente o que o jogador pediu.
      gain += 0.022 * (_weaponLevel / kMaxWeaponLevel);
    }
    if (_weaponLevel >= kMaxWeaponLevel) gain += 0.010;
    if (_weaponLevel <= 1) gain -= 0.024; // fraco → o jogo alivia

    _rank = (_rank + gain * cfg.rankGainMul * dt).clamp(0.0, 1.0);
    rankNotifier.value = _rank;

    if (_rank >= 0.98) achievements.unlock(Achievement.fury);
  }

  void _bumpRank(double amount) {
    _rank = (_rank + amount * cfg.rankGainMul).clamp(0.0, 1.0);
    rankNotifier.value = _rank;
  }

  void _tickChain(double dt) {
    if (_chainTimer <= 0) return;
    _chainTimer -= dt;
    if (_chainTimer <= 0) {
      _chainKills = 0;
      multiplierNotifier.value = 1;
      chainFillNotifier.value = 0;
    } else {
      chainFillNotifier.value = (_chainTimer / _chainWindow).clamp(0.0, 1.0);
    }
  }

  void _applyShake(double dt) {
    const cx = kArenaWidth / 2;
    const cy = kArenaHeight / 2;
    if (_shake <= 0.05) {
      _shake = 0;
      camera.viewfinder.position = Vector2(cx, cy);
      return;
    }
    _shake = math.max(0, _shake - (_shake * 8 + 12) * dt);
    camera.viewfinder.position = Vector2(
      cx + (_rng.nextDouble() - 0.5) * 2 * _shake,
      cy + (_rng.nextDouble() - 0.5) * 2 * _shake,
    );
  }

  // ── Progressão de arma ───────────────────────────────────────────────────

  double _fillPerPickup() {
    switch (_weaponLevel) {
      case 1:
      case 2:
        return 0.5;
      case 3:
      case 4:
        return 1 / 3;
      default:
        return 0.25;
    }
  }

  void _addPower() {
    _bumpRank(0.035); // ficar mais forte provoca o jogo
    if (_weaponLevel >= kMaxWeaponLevel) {
      final bonus = (800 * cfg.scoreMul).round();
      scoreNotifier.value += bonus;
      sfx.play('cap', volume: 0.4);
      _floating('+$bonus', player.position, const Color(0xFFFFD23F), 22);
      return;
    }
    sfx.play('power');
    _powerFill += _fillPerPickup();
    if (_powerFill >= 1.0) {
      _powerFill -= 1.0;
      _weaponLevel++;
      weaponLevelNotifier.value = _weaponLevel;
      _bumpRank(0.05);
      _onWeaponUp();
      if (_weaponLevel >= kMaxWeaponLevel) {
        achievements.unlock(Achievement.maxWeapon);
      }
    }
    powerFillNotifier.value = _powerFill.clamp(0.0, 1.0);
  }

  void _onWeaponUp() {
    sfx.play('weaponup');
    haptics.medium();
    _shake = math.max(_shake, 8);
    sparks.burst(
      x: player.position.x, y: player.position.y,
      color: 3, count: 30, speed: 300, scale: 1.1, life: 0.5,
    );
    final label = _weaponLevel >= kMaxWeaponLevel
        ? 'ARMA MÁXIMA!'
        : 'ARMA Lv.$_weaponLevel';
    // clone: o cascade direto em player.position teleportava a nave 60px.
    _floating(
        label, player.position.clone()..y -= 60, const Color(0xFF35E1F5), 20);
  }

  void _switchWeapon(WeaponType type, Vector2 at) {
    if (type == weaponType) {
      final bonus = (500 * cfg.scoreMul).round();
      scoreNotifier.value += bonus;
      sfx.play('cap', volume: 0.4);
      _floating('+$bonus', at, type.color, 22);
      return;
    }
    sfx.play('weapon');
    haptics.medium();
    weaponTypeNotifier.value = type;
    _usedWeapons.add(type);
    if (_usedWeapons.length == WeaponType.values.length) {
      achievements.unlock(Achievement.allWeapons);
    }
    sparks.burst(
      x: player.position.x, y: player.position.y,
      color: 1, count: 26, speed: 280, scale: 1.0, life: 0.45,
    );
    _floating('${type.label}!', at..y -= 50, type.color, 22);
  }

  void _dropWeapon() {
    if (_weaponLevel > 1) {
      _weaponLevel--;
      weaponLevelNotifier.value = _weaponLevel;
    }
    _powerFill = 0;
    powerFillNotifier.value = 0;
  }

  // ── Pickups, gemas, medalhas ─────────────────────────────────────────────

  void collectPickup(PickupType type, Vector2 at) {
    switch (type) {
      case PickupType.power:
        _addPower();
        sparks.burst(x: at.x, y: at.y, color: 7, count: 8, speed: 160, life: 0.3);
      case PickupType.bomb:
        bombsNotifier.value = math.min(kMaxBombs, bombsNotifier.value + 1);
        sfx.play('cap');
        _floating('BOMBA +1', at, const Color(0xFF35E1F5), 22);
      case PickupType.oneUp:
        _gainLife();
        _floating('1UP', at, const Color(0xFF4BF07A), 24);
      case PickupType.weaponVulcan:
        _switchWeapon(WeaponType.vulcan, at);
      case PickupType.weaponLaser:
        _switchWeapon(WeaponType.laser, at);
      case PickupType.weaponMissile:
        _switchWeapon(WeaponType.missile, at);
    }
  }

  /// Medalha coletada: vale o degrau atual × multiplicador de cadeia, e cada
  /// coleta sobe o degrau. Deixar uma cair (onGemMissed) zera o degrau — o
  /// dilema de milkar a tela sem perder a corrente é o scoring do gênero.
  void collectGem(int _, Vector2 at) {
    final gained = (_medalValue * multiplier * cfg.scoreMul).round();
    scoreNotifier.value += gained;
    // O degrau atual dá o tom: a escada sonora é a corrente audível.
    sfx.medal(_medalIndex, pan: _pan(at.x));
    missions.track(MissionGoal.medals);
    if (_medalIndex < kMedalSteps.length - 1) _medalIndex++;
    medalNotifier.value = _medalValue;
    sparks.burst(x: at.x, y: at.y, color: 5, count: 3, speed: 120, life: 0.25, scale: 0.5);
  }

  void onGemMissed() {
    if (_medalIndex == 0) return;
    _medalIndex = 0;
    medalNotifier.value = 0; // 0 esconde o chip até a próxima coleta
  }

  void _spawnPickup(Vector2 at, PickupType type) =>
      world.add(PowerUp(type: type, at: at));

  void _spawnGems(Vector2 at, int count) {
    for (var i = 0; i < count; i++) {
      world.add(Gem(at: at, value: _medalValue));
    }
  }

  void _gainLife() {
    if (livesNotifier.value < kMaxLives) {
      livesNotifier.value++;
      sfx.play('oneup'); // o jingle sagrado
      haptics.medium();
    }
  }

  void _checkScoreMilestones() {
    final s = scoreNotifier.value;
    if (s >= _nextOneUp) {
      _nextOneUp += cfg.oneUpEvery;
      if (livesNotifier.value < kMaxLives) {
        _gainLife();
        _floating('1UP', player.position, const Color(0xFF4BF07A), 24);
      }
    }
    if (s >= 15000) achievements.unlock(Achievement.score50k);
    if (s >= 40000) achievements.unlock(Achievement.score150k);
  }

  // ── Colisão ────────────────────────────────────────────────────────────

  void _collide() {
    for (final enemy in world.children.whereType<Enemy>().toList()) {
      final damage = playerBullets.hitCircle(
        enemy.position.x, enemy.position.y, enemy.radius,
      );
      if (damage > 0) {
        enemy.damage(damage * _playerBulletDamage);
        // Sem pontos por dano: o autofire é automático, então pagar por bala
        // que encosta é pagar por nada — e era a maior fonte de inflação do
        // placar. O abate paga; a faísca abaixo é o feedback do acerto.
        if (_rng.nextDouble() < 0.5) {
          sparks.burst(
            x: enemy.position.x + (_rng.nextDouble() - 0.5) * enemy.radius,
            y: enemy.position.y + enemy.radius * 0.4,
            color: 6, count: 2, speed: 130, scale: 0.5, life: 0.22,
          );
        }
      }

      // Chefe agonizando não colide: a agonia é espetáculo, não armadilha.
      if (player.vulnerable && !enemy.dying) {
        final dx = enemy.position.x - player.position.x;
        final dy = enemy.position.y - player.position.y;
        final rr = enemy.radius + kPlayerHitRadius;
        if (dx * dx + dy * dy <= rr * rr) _playerHit();
      }
    }

    final struck = enemyBullets.checkPlayer(
      px: player.position.x,
      py: player.position.y,
      hitRadius: kPlayerHitRadius,
      grazeRadius: kGrazeRadius,
      vulnerable: player.vulnerable,
      onGraze: _onGraze,
    );
    if (struck) _playerHit();
  }

  void _onGraze() {
    grazeNotifier.value++;
    scoreNotifier.value += (30 * cfg.scoreMul).round();
    sfx.graze();
    missions.track(MissionGoal.graze);
    if (grazeNotifier.value >= 100) achievements.unlock(Achievement.graze100);
  }

  void _playerHit() {
    // Escudo do módulo absorve o dano e entra em recarga — sem perder nave.
    if (_shieldUp) {
      _shieldUp = false;
      _shieldCd = _shieldRechargeS;
      shieldNotifier.value = false;
      player.onHit(); // breve invulnerabilidade para não tomar dois seguidos
      enemyBullets.clear(null);
      world.add(Shockwave(player.position.clone()));
      sfx.play('shield');
      haptics.heavy();
      _shake = 18;
      _floating('ESCUDO!', player.position.clone()..y -= 60,
          const Color(0xFF35E1F5), 22);
      return;
    }

    player.onHit();
    livesNotifier.value--;
    _dropWeapon();
    sfx.play('death');
    haptics.heavy();
    // O momento mais importante da run ganha peso: congela e estica.
    _hitstop = math.max(_hitstop, 0.08);
    _slowmo = 0.55;
    if (_bossAlive) _bossHitTaken = true;

    // Morrer relaxa a fúria (o clássico "morrer baixa o rank") e quebra tudo.
    _bumpRank(-0.34);
    _chainKills = 0;
    _chainTimer = 0;
    multiplierNotifier.value = 1;
    chainFillNotifier.value = 0;
    _medalIndex = 0;
    medalNotifier.value = 0;
    _shake = 26;

    sparks.burst(
      x: player.position.x, y: player.position.y,
      color: 0, count: 44, speed: 420, scale: 1.3, life: 0.75,
    );
    enemyBullets.clear(null);
    world.add(Shockwave(player.position.clone()));

    if (livesNotifier.value <= 0) {
      _over = true;
      missions.track(MissionGoal.score, value: scoreNotifier.value);
      missions.track(MissionGoal.wave, value: _wave);
      recorder?.finish(score: scoreNotifier.value, wave: _wave);
      onGameOver(scoreNotifier.value, grazeNotifier.value, _wave);
    }
  }

  /// Volta do game over (recompensa de anúncio): 2 naves, tela limpa, fúria
  /// aliviada e um respiro de invulnerabilidade. Uma vez por partida — quem
  /// decide o limite é a UI.
  void revive() {
    if (!_over) return;
    _over = false;
    recorder?.event('revive');
    livesNotifier.value = 2;
    bombsNotifier.value = math.max(bombsNotifier.value, 1);
    _bumpRank(-0.4);
    enemyBullets.clear(null);
    for (final enemy in world.children.whereType<Enemy>().toList()) {
      if (!enemy.isBoss) enemy.damage(140);
    }
    world.add(Shockwave(player.position.clone()));
    player.invuln = 3.0;
    sfx.play('oneup');
    haptics.medium();
    _floating('DE VOLTA!', player.position.clone()..y -= 70,
        const Color(0xFF4BF07A), 24);
  }

  // ── Bomba ──────────────────────────────────────────────────────────────

  void useBomb() {
    if (_over || bombsNotifier.value <= 0) return;
    bombsNotifier.value--;
    _bumpRank(-0.06); // alívio momentâneo
    sfx.play('bomb');
    sfx.duck(); // música abaixa: o estouro parece o dobro
    haptics.heavy();
    missions.track(MissionGoal.bombs);
    recorder?.event('bomb');

    final cleared = enemyBullets.clear((x, y, sprite) {
      if (_rng.nextDouble() < 0.18) {
        sparks.burst(x: x, y: y, color: 3, count: 2, speed: 150, life: 0.3);
      }
    });
    scoreNotifier.value += (cleared * 12 * cfg.scoreMul).round();

    for (final enemy in world.children.whereType<Enemy>().toList()) {
      enemy.damage(140);
    }

    world.add(Shockwave(player.position.clone()));
    _floating(
      cleared > 0 ? 'BOMBA  +${(cleared * 12 * cfg.scoreMul).round()}' : 'BOMBA',
      player.position.clone()..y -= 70,
      const Color(0xFF35E1F5),
      24,
    );
    player.invuln = math.max(player.invuln, 1.4);
    _shake = 24;
  }

  // ── Chefe: fases, agonia e novos papéis ──────────────────────────────────

  void onBossPhase(Enemy boss, int index) {
    sfx.play('phase');
    haptics.medium();
    hitstop(0.12); // a virada de fase é um soco: 7 frames de silêncio
    _shake = math.max(_shake, 18);
    // Alívio ao virar a fase: limpa a tela, como fazem os chefes bons.
    enemyBullets.clear(null);
    world.add(Shockwave(boss.position.clone()));
    _floating(
      'FASE ${index + 1}',
      boss.position.clone()..y += 70,
      const Color(0xFFFF4FD8),
      26,
    );
    _spawnGems(boss.position, 4);
  }

  /// O chefe entrou em agonia: limpa as balas dele e deixa a sequência de
  /// explosões correr (Enemy chama [onBossDeathTick] até o estouro final).
  void onBossDying(Enemy boss) {
    enemyBullets.clear(null);
    sfx.explosionMed();
    _shake = math.max(_shake, 14);
  }

  /// Uma explosão da cadeia de agonia do chefe.
  void onBossDeathTick(Enemy boss) {
    final r = boss.radius;
    sparks.burst(
      x: boss.position.x + (_rng.nextDouble() - 0.5) * r * 1.8,
      y: boss.position.y + (_rng.nextDouble() - 0.5) * r * 1.6,
      color: _rng.nextBool() ? 7 : 5,
      count: 14,
      speed: 260,
      scale: 1.0,
      life: 0.45,
    );
    sfx.explosionSmall(pan: _pan(boss.position.x));
    _shake = math.max(_shake, 9);
  }

  /// Sniper travou a mira no jogador — o aviso sonoro do perigo telegrafado.
  void onSniperLock(Enemy sniper) {
    sfx.play('lock', volume: 0.55, pan: _pan(sniper.position.x));
  }

  /// Sniper dispara: 3 dardos rápidos na linha telegrafada.
  void sniperFire(Enemy sniper, Vector2 dir) {
    final speed = 470 * fireContext.speedScale;
    for (var i = 0; i < 3; i++) {
      enemyBullets.spawn(
        x: sniper.position.x - dir.x * i * 34,
        y: sniper.position.y - dir.y * i * 34,
        vx: dir.x * speed,
        vy: dir.y * speed,
        shape: BulletShape.dart,
        color: 2,
        scale: 0.9,
      );
    }
  }

  /// Alguém da formação fugiu: bônus perdido.
  void onFormationBroken(int id) => _formations.remove(id);

  /// Registra uma formação de [size] membros e devolve o id dela.
  int registerFormation(int size) {
    final id = _formationSeq++;
    _formations[id] = size;
    return id;
  }

  // ── Ondas ──────────────────────────────────────────────────────────────

  void _tickWaves(double dt) {
    if (world.children.whereType<Enemy>().any((e) => e.isBoss)) return;

    _waveCd -= dt;
    if (_waveCd > 0) return;

    _spawnWave(_wave++);
    waveNotifier.value = _wave;
    missions.track(MissionGoal.wave, value: _wave);
    if (_wave >= 10) achievements.unlock(Achievement.wave10);
  }

  /// O cigarro depois do chefe: bônus de fim de estágio contando um a um.
  /// (Os valores entram no placar aqui; a UI só teatraliza.)
  void _showStageTally() {
    final cleared = _stage - 1; // o estágio recém-vencido
    final noMiss = _bossHitTaken ? 0 : (6000 * cleared * cfg.scoreMul).round();
    final grazeStage = grazeNotifier.value - _grazeAtStage;
    final grazeBonus = (grazeStage * 12 * cfg.scoreMul).round();
    final medalBonus = (_medalIndex * 800 * cfg.scoreMul).round();
    _grazeAtStage = grazeNotifier.value;
    scoreNotifier.value += noMiss + grazeBonus + medalBonus;
    stageClearNotifier.value =
        (stage: cleared, noMiss: noMiss, graze: grazeBonus, medal: medalBonus);
  }

  void _spawnWave(int index) {
    const w = kArenaWidth;

    // Inimigos ficam mais duros conforme o jogo avança (~5%/onda, teto 3,2×).
    kit.waveScale = (1 + index * 0.05).clamp(1.0, 3.2);

    switch (index) {
      case 0:
        world.add(kit.easyGrunt(w * 0.5));
        _waveCd = 3.4 + cfg.waveCdBonus;
        return;
      case 1:
        world.add(kit.easyGrunt(w * 0.35));
        world.add(kit.easyGrunt(w * 0.65));
        _waveCd = 3.4 + cfg.waveCdBonus;
        return;
      case 2:
        for (var i = 0; i < 3; i++) {
          world.add(kit.easyGrunt(w * (i + 1) / 4, colorIndex: 4));
        }
        _waveCd = 3.6 + cfg.waveCdBonus;
        return;
      case 3:
        world.add(kit.grunt(w * 0.3));
        world.add(kit.grunt(w * 0.7));
        _waveCd = 3.8 + cfg.waveCdBonus;
        return;
      case 4:
        world.add(kit.spinner(w * 0.5));
        _waveCd = 4.0 + cfg.waveCdBonus;
        return;
    }

    if (index == 9 || (index > 9 && (index - 9) % 8 == 0)) {
      _stage++;
      stageNotifier.value = _stage;
      _bossAlive = true;
      _bossHitTaken = false;
      world.add(kit.boss(_stage));
      final title = bossTitle(_stage);
      bossNameNotifier.value = title;
      world.add(AnnounceBanner(title, stripes: true, blinkIcon: true));
      sfx.play('alarm');
      sfx.bossMode(true); // crossfade para o tema de chefe
      _waveCd = 14;
      return;
    }

    // Mid-boss (ELITE) no meio de cada estágio: o pedágio antes do chefe.
    if (index > 9 && (index - 9) % 8 == 4) {
      world.add(kit.midBoss(_stage));
      world.add(kit.grunt(w * 0.2));
      world.add(kit.grunt(w * 0.8));
      // Mesmo padrão de faixa dos outros anúncios, na cor de elite.
      world.add(AnnounceBanner(
        'ELITE NA ÁREA',
        accent: const Color(0xFFFFD23F),
        duration: 1.6,
      ));
      sfx.play('phase', volume: 0.7);
      _waveCd = 8.0;
      return;
    }

    // Formação em V: aniquilar TODAS as 5 paga bônus (lição de Galaga).
    if (index > 9 && index % 6 == 2 && _rng.nextDouble() < 0.6) {
      final id = registerFormation(5);
      for (final e in kit.formationV(id)) {
        world.add(e);
      }
      _waveCd = (4.8 + cfg.waveCdBonus) * (1 - 0.35 * _rank);
      return;
    }

    final tier = math.min((index - 5) ~/ 6, 3);
    switch (index % 6) {
      case 0:
        for (var i = 0; i < 2 + tier; i++) {
          world.add(kit.grunt(w * (i + 1) / (3 + tier)));
        }
        if (tier >= 2) world.add(kit.heavy(w * 0.5));
      case 1:
        world.add(kit.spinner(w * 0.4));
        world.add(kit.grunt(w * 0.72));
        if (tier >= 1) world.add(kit.spinner(w * 0.72, colorIndex: 6));
        // Sniper estreia no estágio 2: pune quem acampa num canto.
        if (_stage >= 2) world.add(kit.sniper(w * 0.15));
      case 2:
        for (var i = 0; i < 3; i++) {
          world.add(kit.grunt(w * (i + 1) / 4, colorIndex: 4));
        }
        if (tier >= 2) world.add(kit.heavy(w * 0.3, colorIndex: 7));
      case 3:
        world.add(kit.ringer(w * 0.5));
        world.add(kit.grunt(w * 0.22));
        if (tier >= 1) world.add(kit.heavy(w * 0.78));
        if (_stage >= 2) world.add(kit.sniper(w * 0.85));
      case 4:
        world.add(kit.runner(240, true));
        world.add(kit.runner(360, false));
        if (tier >= 2) world.add(kit.runner(150, false, colorIndex: 7));
        // Kamikazes estreiam no estágio 3: mergulham em quem dorme.
        if (_stage >= 3) {
          world.add(kit.kamikaze(w * (0.25 + _rng.nextDouble() * 0.5)));
          world.add(kit.kamikaze(w * (0.25 + _rng.nextDouble() * 0.5)));
        }
      case 5:
        world.add(kit.ringer(w * 0.35, colorIndex: 3));
        world.add(kit.grunt(w * 0.7));
        if (tier >= 1) world.add(kit.spinner(w * 0.55, colorIndex: 6));
        if (tier >= 3) world.add(kit.heavy(w * 0.5, colorIndex: 1));
        // Cargueiro estreia no estágio 4: a piñata de medalhas.
        if (_stage >= 4) world.add(kit.freighter(_rng.nextBool()));
    }

    // A FÚRIA manda reforços: quanto mais forte o jogador, mais naves vêm.
    for (var i = 0; i < _extraEnemies; i++) {
      world.add(kit.grunt(w * (0.15 + _rng.nextDouble() * 0.7),
          colorIndex: 7));
    }

    // Rank alto também aperta o ritmo entre ondas.
    _waveCd = (4.8 + cfg.waveCdBonus) * (1 - 0.35 * _rank);
  }

  void onEnemyKilled(Enemy enemy) {
    achievements.unlock(Achievement.firstBlood);
    killsThisRun++;
    missions.track(MissionGoal.kills);
    missions.track(switch (weaponType) {
      WeaponType.vulcan => MissionGoal.killsVulcan,
      WeaponType.laser => MissionGoal.killsLaser,
      WeaponType.missile => MissionGoal.killsMissile,
    });

    _chainKills++;
    _chainTimer = _chainWindow;
    multiplierNotifier.value = multiplier;
    chainFillNotifier.value = 1.0;
    if (multiplier >= 2) achievements.unlock(Achievement.chain2);
    if (multiplier >= 4) achievements.unlock(Achievement.chain4);

    final gained = (enemy.scoreValue * multiplier * cfg.scoreMul).round();
    scoreNotifier.value += gained;

    // Formação: o grupo inteiro caiu? Bônus de aniquilação.
    final fid = enemy.formationId;
    if (fid != null && _formations.containsKey(fid)) {
      final left = _formations[fid]! - 1;
      if (left <= 0) {
        _formations.remove(fid);
        final bonus = (2500 * _stage * cfg.scoreMul).round();
        scoreNotifier.value += bonus;
        sfx.play('weapon');
        haptics.medium();
        _floating('FORMAÇÃO!  +$bonus', enemy.position.clone()..y -= 40,
            const Color(0xFF35E1F5), 24);
      } else {
        _formations[fid] = left;
      }
    }

    if (enemy.isBoss) {
      sfx.explosionBoss();
      sfx.bossMode(false); // a música volta ao tema normal
      haptics.heavy();
      hitstop(0.22);
      world.add(ScreenFlash());
    } else {
      if (enemy.radius >= 26) {
        sfx.explosionMed(pan: _pan(enemy.position.x));
        hitstop(0.04); // abate pesado tem peso; o miúdo mantém o fluxo
      } else {
        sfx.explosionSmall(pan: _pan(enemy.position.x));
      }
      haptics.light();
    }

    sparks.burst(
      x: enemy.position.x, y: enemy.position.y,
      color: enemy.isBoss ? 5 : 7,
      count: enemy.isBoss ? 120 : 26,
      speed: enemy.isBoss ? 620 : 320,
      scale: enemy.isBoss ? 2.2 : 1.1,
      life: enemy.isBoss ? 1.2 : 0.55,
    );
    _floating(
      multiplier > 1 ? '+$gained ×$multiplier' : '+$gained',
      enemy.position.clone(),
      enemy.isBoss ? const Color(0xFFFFD23F) : Colors.white,
      enemy.isBoss ? 30 : 20,
    );
    _shake = math.max(_shake, enemy.isBoss ? 30 : 5);

    if (enemy.isBoss) {
      _bossAlive = false;
      bossNameNotifier.value = null;
      achievements.unlock(Achievement.firstBoss);
      missions.track(MissionGoal.boss);
      if (!_bossHitTaken) achievements.unlock(Achievement.noMissBoss);
      // LENDA destrava derrubando um chefe no VETERANO.
      if (difficulty == Difficulty.hard) settings.unlockLegend();

      for (var i = 0; i < 3; i++) {
        _spawnPickup(enemy.position.clone()..x += (i - 1) * 60, PickupType.power);
      }
      _spawnPickup(enemy.position.clone()..y += 40, PickupType.bomb);
      _spawnPickup(enemy.position.clone()..x += 90, PickupType.oneUp);
      _spawnPickup(enemy.position.clone()..x -= 90, _randomOtherWeapon());
      _spawnGems(enemy.position, 14);

      _showStageTally();
      // O setor novo tem outra cara: o fundo transiciona junto com o tally.
      starfield.setStage(_stage);
      _waveCd = 6.5;
      return;
    }

    // Elite (mid-boss): paga arma garantida + chuva de gemas.
    if (enemy.elite) {
      _spawnPickup(enemy.position.clone(), _randomOtherWeapon());
      _spawnPickup(enemy.position.clone()..x += 60, PickupType.power);
      _spawnGems(enemy.position, 8);
      return;
    }

    // Cargueiro: a piñata estoura.
    if (enemy.medalCarrier) {
      _spawnGems(enemy.position, 7);
      _spawnPickup(enemy.position.clone(), PickupType.power);
      return;
    }

    _spawnGems(enemy.position, 2 + _rng.nextInt(2));

    if (_rng.nextDouble() < cfg.oneUpDropChance) {
      _spawnPickup(enemy.position.clone(), PickupType.oneUp);
      return;
    }

    _killsSinceWeapon++;
    if (_killsSinceWeapon >= 14) {
      _killsSinceWeapon = 0;
      _spawnPickup(enemy.position.clone(), _randomOtherWeapon());
      return;
    }

    _killsSinceDrop++;
    if (_killsSinceDrop >= 4) {
      _killsSinceDrop = 0;
      _spawnPickup(enemy.position.clone(), PickupType.power);
    } else if (_rng.nextDouble() < 0.10) {
      _spawnPickup(enemy.position.clone(), PickupType.power);
    } else if (_rng.nextDouble() < 0.04) {
      _spawnPickup(enemy.position.clone(), PickupType.bomb);
    }
  }

  PickupType _randomOtherWeapon() {
    final options = <PickupType>[
      if (weaponType != WeaponType.vulcan) PickupType.weaponVulcan,
      if (weaponType != WeaponType.laser) PickupType.weaponLaser,
      if (weaponType != WeaponType.missile) PickupType.weaponMissile,
    ];
    return options[_rng.nextInt(options.length)];
  }

  void _floating(String text, Vector2 pos, Color color, double size,
      {double duration = 0.8}) {
    world.add(FloatingText(
      text,
      position: pos.clone(),
      color: color,
      fontSize: size,
      duration: duration,
    ));
  }
}
