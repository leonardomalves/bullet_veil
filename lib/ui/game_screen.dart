import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../core/achievements.dart';
import '../core/ads.dart';
import '../core/daily.dart';
import '../core/garage.dart';
import '../core/haptics.dart';
import '../core/high_scores.dart';
import '../core/missions.dart';
import '../core/replay.dart';
import '../core/settings.dart';
import '../core/sfx.dart';
import '../core/stats.dart';
import '../game/arena.dart';
import '../game/danmaku_game.dart';
import '../game/difficulty.dart';
import '../game/player.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.difficulty = Difficulty.normal,
    this.daily = false,
  });

  final Difficulty difficulty;

  /// Desafio diário: seed fixa, uma tentativa, sem "de novo".
  final bool daily;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late DanmakuGame _game;
  ({int score, int graze, int wave})? _result;
  bool _newRecord = false;

  // Pause: menu aberto e/ou contagem 3-2-1 de retomada.
  bool _paused = false;
  int? _countdown;
  int _resumeToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = _build();
    sfx.startMusic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Saiu com o resultado na tela (back do sistema etc.): grava mesmo assim.
    if (!_finalized && _result != null) _finalizeRun();
    sfx.stopMusic();
    super.dispose();
  }

  /// Ligação, troca de app, tela apagada: pausa sozinho. Voltar é manual —
  /// ninguém quer ressuscitar no meio de uma cortina de balas.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause(sound: false);
  }

  int _creditsEarned = 0;

  // Revive por anúncio: 1 por partida. A gravação do recorde/créditos fica
  // ADIADA até o jogador decidir não continuar — senão o revive contaria
  // créditos em dobro.
  bool _revived = false;
  bool _finalized = false;
  int _creditsMul = 1;

  DanmakuGame _build() => DanmakuGame(
        difficulty: widget.difficulty,
        skin: garage.skin,
        modules: garage.equipped,
        moduleLevels: garage.equippedLevels,
        daily: widget.daily,
        seed: widget.daily ? daily.seed : null,
        onGameOver: (score, graze, wave) {
          sfx.fadeOutMusic();
          sfx.play('gameover');
          _creditsEarned = Garage.creditsFor(score);
          if (!mounted) return;
          setState(() {
            _result = (score: score, graze: graze, wave: wave);
            // Tentativo: só persiste em _finalizeRun.
            _newRecord = score > highScores.of(widget.difficulty);
          });
        },
      )..pauseWhenBackgrounded = false; // lifecycle é conosco (retomada manual)

  /// Grava recorde, créditos (com o dobro do anúncio, se houver), stats e
  /// missões — uma única vez por partida encerrada de verdade.
  Future<void> _finalizeRun() async {
    final r = _result;
    if (_finalized || r == null) return;
    _finalized = true;
    await highScores.record(widget.difficulty, r.score);
    await garage.addCredits(_creditsEarned * _creditsMul);
    await stats.recordRun(
      score: r.score,
      wave: r.wave,
      kills: _game.killsThisRun,
      seconds: _game.elapsedSeconds.round(),
    );
    await missions.flush();
    if (widget.daily) {
      await daily.record(r.score);
      // Evidência da run guardada — o upload da F1 lê daqui.
      final rec = _game.recorder;
      if (rec != null) await ReplayVault.saveDaily(rec);
    }
  }

  /// Recompensa do anúncio: a nave volta. O resultado ainda não foi gravado,
  /// então a partida simplesmente continua de onde parou.
  void _reviveFromAd() {
    if (_revived || _result == null) return;
    ads.showRewarded(onReward: () {
      if (!mounted) return;
      setState(() {
        _revived = true;
        _result = null;
        _newRecord = false;
      });
      _game.revive();
      sfx.startMusic();
    });
  }

  void _doubleCreditsFromAd() {
    if (_creditsMul > 1 || _result == null) return;
    ads.showRewarded(onReward: () {
      if (!mounted) return;
      setState(() => _creditsMul = 2);
    });
  }

  Future<void> _restart() async {
    await _finalizeRun();
    _resumeToken++;
    if (!mounted) return;
    setState(() {
      _result = null;
      _newRecord = false;
      _paused = false;
      _countdown = null;
      _revived = false;
      _finalized = false;
      _creditsMul = 1;
      _creditsEarned = 0;
      _game = _build();
    });
    sfx.startMusic();
  }

  void _pause({bool sound = true}) {
    if (_result != null) return;
    if (_paused && _countdown == null) return; // já está no menu de pause
    _resumeToken++; // cancela contagem em andamento, se houver
    setState(() {
      _paused = true;
      _countdown = null;
    });
    _game.pauseEngine();
    sfx.pauseMusic();
    if (sound) sfx.play('ui_tap');
  }

  Future<void> _resume() async {
    if (!_paused || _countdown != null) return;
    final token = ++_resumeToken;
    for (var n = 3; n >= 1; n--) {
      if (!mounted || !_paused || _resumeToken != token) return;
      setState(() => _countdown = n);
      sfx.play('count_${4 - n}'); // pitch sobe conforme chega no GO
      await Future.delayed(const Duration(milliseconds: 650));
    }
    if (!mounted || !_paused || _resumeToken != token) return;
    setState(() {
      _countdown = null;
      _paused = false;
    });
    sfx.play('count_go', volume: 0.7);
    _game.resumeEngine();
    sfx.resumeMusic();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05030F),
      body: Stack(
        children: [
          GameWidget(key: ValueKey(_game), game: _game),
          SafeArea(child: _Hud(game: _game)),
          const SafeArea(child: _AchievementToast()),
          const SafeArea(child: _MissionToast()),
          if (_result == null) ...[
            SafeArea(child: _StageTally(game: _game)),
            SafeArea(
              child: ListenableBuilder(
                listenable: settings,
                builder: (context, _) => Align(
                  // Canhoto joga com a bomba na esquerda.
                  alignment: settings.leftHanded
                      ? Alignment.bottomLeft
                      : Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: 22, right: 22, bottom: 30),
                    child: _BombButton(game: _game, paused: _paused),
                  ),
                ),
              ),
            ),
            if (!_paused)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _PauseButton(onTap: _pause),
                ),
              ),
            _StageIntro(difficulty: widget.difficulty),
            if (!settings.tutorialDone && !widget.daily)
              SafeArea(child: _TutorialCoach(game: _game)),
          ],
          if (_paused)
            Positioned.fill(
              child: _PauseOverlay(
                countdown: _countdown,
                onResume: _resume,
                onRestart: _restart,
                onMenu: () => Navigator.of(context).pop(),
              ),
            ),
          if (_result != null)
            Positioned.fill(
              child: _GameOver(
                result: _result!,
                newRecord: _newRecord,
                difficulty: widget.difficulty,
                creditsEarned: _creditsEarned * _creditsMul,
                creditsDoubled: _creditsMul > 1,
                daily: widget.daily,
                onRevive:
                    (!_revived && !widget.daily) ? _reviveFromAd : null,
                onDoubleCredits: (_creditsMul == 1 && _creditsEarned > 0)
                    ? _doubleCreditsFromAd
                    : null,
                onRestart: _restart,
                onMenu: () async {
                  await _finalizeRun();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pause ────────────────────────────────────────────────────────────────

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(color: Colors.white24, width: 1.2),
        ),
        child: const Icon(Icons.pause_rounded, color: Colors.white70, size: 20),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.countdown,
    required this.onResume,
    required this.onRestart,
    required this.onMenu,
  });

  final int? countdown;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    // Contagem 3-2-1: só o número, o campo de batalha visível atrás.
    if (countdown != null) {
      return Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: Text(
          '$countdown',
          key: ValueKey(countdown),
          style: const TextStyle(
            fontSize: 110,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            shadows: [Shadow(color: Color(0xFF35E1F5), blurRadius: 30)],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.86),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAUSADO',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            _PauseAction(
              label: 'CONTINUAR',
              filled: true,
              onTap: onResume,
            ),
            const SizedBox(height: 12),
            _PauseAction(label: 'REINICIAR', onTap: onRestart),
            const SizedBox(height: 12),
            _PauseAction(label: 'MENU', onTap: onMenu),
            const SizedBox(height: 34),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SettingChip(
                  icon: Icons.volume_up_rounded,
                  label: 'SOM',
                  value: () => sfx.enabled,
                  onChanged: (v) => sfx.enabled = v,
                ),
                const SizedBox(width: 14),
                _SettingChip(
                  icon: Icons.vibration_rounded,
                  label: 'VIBRAÇÃO',
                  value: () => haptics.enabled,
                  onChanged: (v) => haptics.enabled = v,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sensibilidade do arrasto: 1x → 1.5x → 2x.
                const _SensitivityChip(),
                const SizedBox(width: 14),
                _SettingChip(
                  icon: Icons.swap_horiz_rounded,
                  label: 'CANHOTO',
                  value: () => settings.leftHanded,
                  onChanged: (v) => settings.leftHanded = v,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip que cicla a sensibilidade do arrasto (1x/1.5x/2x).
class _SensitivityChip extends StatefulWidget {
  const _SensitivityChip();

  @override
  State<_SensitivityChip> createState() => _SensitivityChipState();
}

class _SensitivityChipState extends State<_SensitivityChip> {
  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF35E1F5);
    final label = settings.sensitivity == 1.0
        ? '1x'
        : settings.sensitivity == 1.5
            ? '1.5x'
            : '2x';
    return GestureDetector(
      onTap: () {
        settings.cycleSensitivity();
        sfx.play('ui_tap');
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: cyan.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cyan, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed_rounded, size: 16, color: cyan),
            const SizedBox(width: 6),
            Text(
              'ARRASTO $label',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseAction extends StatelessWidget {
  const _PauseAction({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        sfx.play('ui_tap');
        onTap();
      },
      child: Container(
        width: 230,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF35E1F5) : null,
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            color: filled ? const Color(0xFF05030F) : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// Toggle persistente (som/vibração) — muda na hora, sem sair do jogo.
class _SettingChip extends StatefulWidget {
  const _SettingChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool Function() value;
  final ValueChanged<bool> onChanged;

  @override
  State<_SettingChip> createState() => _SettingChipState();
}

class _SettingChipState extends State<_SettingChip> {
  @override
  Widget build(BuildContext context) {
    final on = widget.value();
    const cyan = Color(0xFF35E1F5);
    return GestureDetector(
      onTap: () {
        widget.onChanged(!on);
        sfx.play('ui_tap');
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? cyan.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: on ? cyan : Colors.white24, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 16, color: on ? cyan : Colors.white38),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: on ? Colors.white : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ícone de nave (vidas) ──────────────────────────────────────────────────

class _ShipIcon extends StatelessWidget {
  const _ShipIcon({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _ShipPainter(active)),
    );
  }
}

class _ShipPainter extends CustomPainter {
  _ShipPainter(this.active);

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.5, h * 0.72)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = active ? const Color(0xFFE8F4FF) : Colors.white24,
    );
    if (active) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF35E1F5),
      );
    }
  }

  @override
  bool shouldRepaint(_ShipPainter old) => old.active != active;
}

// ── HUD ──────────────────────────────────────────────────────────────────

class _Hud extends StatelessWidget {
  const _Hud({required this.game});

  final DanmakuGame game;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder(
                    valueListenable: game.scoreNotifier,
                    builder: (context, score, _) => Text(
                      '$score',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      ValueListenableBuilder(
                        valueListenable: game.grazeNotifier,
                        builder: (context, graze, _) => Text(
                          'GRAZE $graze',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: Color(0xFF35E1F5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ValueListenableBuilder(
                        valueListenable: game.medalNotifier,
                        builder: (context, medal, _) => medal <= 0
                            ? const SizedBox.shrink()
                            : Text(
                                'MEDALHA $medal',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: Color(0xFFFFD23F),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Naves = vidas.
                  ValueListenableBuilder(
                    valueListenable: game.livesNotifier,
                    builder: (context, lives, _) => Row(
                      children: [
                        for (var i = 0; i < kMaxLives; i++)
                          if (i < lives || i < kStartLives)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: _ShipIcon(active: i < lives),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder(
                        valueListenable: game.stageNotifier,
                        builder: (context, stage, _) => Text(
                          'EST. $stage · ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                      ValueListenableBuilder(
                        valueListenable: game.waveNotifier,
                        builder: (context, wave, _) => Text(
                          'ONDA $wave',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BossBar(game: game),
          const SizedBox(height: 8),
          _PowerMeter(game: game),
          const SizedBox(height: 5),
          _FuryBar(game: game),
          const SizedBox(height: 6),
          Row(
            children: [
              // Telemetria é ferramenta de dev — não vaza pro jogador.
              if (kDebugMode) _Telemetry(game: game),
              const Spacer(),
              _ChainChip(game: game),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barra de FÚRIA (rank). Mostrar o medidor — que os clássicos escondem —
/// vira mecânica visível: ficar forte enche a barra e traz mais inimigos;
/// morrer alivia.
class _FuryBar extends StatelessWidget {
  const _FuryBar({required this.game});

  final DanmakuGame game;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'FÚRIA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Color(0xFFFF8A3D),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: game.rankNotifier,
            builder: (context, rank, _) {
              final hot = rank > 0.75;
              return Container(
                height: 7,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: rank.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD23F), Color(0xFFFF3B5C)],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: hot
                          ? [
                              const BoxShadow(
                                color: Color(0xFFFF3B5C),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Toast de condecoração desbloqueada. Consome `achievements.pending`,
/// mostrando um de cada vez no topo.
class _AchievementToast extends StatefulWidget {
  const _AchievementToast();

  @override
  State<_AchievementToast> createState() => _AchievementToastState();
}

class _AchievementToastState extends State<_AchievementToast> {
  Achievement? _current;
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    achievements.addListener(_onChange);
  }

  @override
  void dispose() {
    achievements.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (_current == null) _next();
  }

  Future<void> _next() async {
    final a = achievements.takePending();
    if (a == null) return;
    if (!mounted) return;
    setState(() {
      _current = a;
      _opacity = 1;
    });
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    setState(() => _opacity = 0);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _current = null);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final a = _current;
    if (a == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 96),
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: const Duration(milliseconds: 320),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0618).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFFD23F).withValues(alpha: 0.7),
                    width: 1.2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '★ CONDECORAÇÃO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFFFFD23F),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${a.title}  +${a.reward}¢',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Toast de missão diária cumprida — paga na hora, avisa na hora.
class _MissionToast extends StatefulWidget {
  const _MissionToast();

  @override
  State<_MissionToast> createState() => _MissionToastState();
}

class _MissionToastState extends State<_MissionToast> {
  String? _current;
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    missions.addListener(_onChange);
  }

  @override
  void dispose() {
    missions.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (_current == null) _next();
  }

  Future<void> _next() async {
    final label = missions.takePending();
    if (label == null || !mounted) return;
    setState(() {
      _current = label;
      _opacity = 1;
    });
    sfx.play('oneup', volume: 0.5);
    await Future.delayed(const Duration(milliseconds: 1900));
    if (!mounted) return;
    setState(() => _opacity = 0);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _current = null);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final label = _current;
    if (label == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 148),
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: const Duration(milliseconds: 320),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0618).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF4BF07A).withValues(alpha: 0.7),
                    width: 1.2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '✔ MISSÃO CUMPRIDA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFF4BF07A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Primeira run guiada: 4 lições no ritmo do jogador, sem parar o jogo.
/// Ensina as mecânicas que fazem o jogo ser bom — graze, bomba, medalha.
class _TutorialCoach extends StatefulWidget {
  const _TutorialCoach({required this.game});

  final DanmakuGame game;

  @override
  State<_TutorialCoach> createState() => _TutorialCoachState();
}

class _TutorialCoachState extends State<_TutorialCoach> {
  int _step = 0;
  late final int _startBombs = widget.game.bombsNotifier.value;

  static const _cyan = Color(0xFF35E1F5);

  @override
  void initState() {
    super.initState();
    widget.game.movedNotifier.addListener(_check);
    widget.game.grazeNotifier.addListener(_check);
    widget.game.bombsNotifier.addListener(_check);
  }

  @override
  void dispose() {
    widget.game.movedNotifier.removeListener(_check);
    widget.game.grazeNotifier.removeListener(_check);
    widget.game.bombsNotifier.removeListener(_check);
    super.dispose();
  }

  void _advance() {
    if (!mounted) return;
    setState(() => _step++);
    if (_step == 3) {
      // Última lição é temporizada; depois, formatura.
      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _step = 4);
        settings.markTutorialDone();
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _step = 5);
        });
      });
    }
  }

  void _check() {
    final g = widget.game;
    switch (_step) {
      case 0:
        if (g.movedNotifier.value >= 220) _advance();
      case 1:
        if (g.grazeNotifier.value >= 3) _advance();
      case 2:
        if (g.bombsNotifier.value < _startBombs) _advance();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step >= 5) return const SizedBox.shrink();
    final (text, sub) = switch (_step) {
      0 => ('ARRASTE para mover', 'qualquer lugar da tela'),
      1 => ('Passe PERTO das balas', 'raspar sem tocar = GRAZE = pontos'),
      2 => ('TOQUE na BOMBA', 'limpa a tela quando apertar'),
      3 => ('Medalhas douradas', 'colete SEM deixar cair — o valor SOBE'),
      _ => ('BOA CAÇADA, PILOTO', ''),
    };
    return Align(
      alignment: const Alignment(0, 0.52),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(_step),
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0618).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cyan, width: 1.4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_step < 4)
            GestureDetector(
              onTap: () {
                settings.markTutorialDone();
                setState(() => _step = 5);
              },
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'pular tutorial',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white38,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white38,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Multiplicador de cadeia: aparece a partir de ×2 com uma barrinha do tempo
/// restante — o jogador vê o ×4 escorrendo e sai caçando o próximo abate.
class _ChainChip extends StatelessWidget {
  const _ChainChip({required this.game});

  final DanmakuGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.multiplierNotifier,
      builder: (context, mult, _) {
        if (mult < 2) return const SizedBox.shrink();
        const color = Color(0xFFFFD23F);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 120),
              child: Text(
                '×$mult',
                key: ValueKey(mult),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                ),
              ),
            ),
            const SizedBox(height: 3),
            ValueListenableBuilder(
              valueListenable: game.chainFillNotifier,
              builder: (context, fill, _) => Container(
                width: 52,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fill,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Barra do chefe com NOME, preenchimento dramático de entrada e pips das
/// fases — o jogador vê que a luta tem 3 atos e onde está.
class _BossBar extends StatelessWidget {
  const _BossBar({required this.game});

  final DanmakuGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.bossHpNotifier,
      builder: (context, hp, _) {
        if (hp == null) return const SizedBox(height: 8);
        return ValueListenableBuilder(
          valueListenable: game.bossNameNotifier,
          builder: (context, name, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFFFF4FD8),
                    ),
                  ),
                ),
              // A key pelo nome faz a barra ENCHER (0→hp) a cada chefe novo.
              TweenAnimationBuilder<double>(
                key: ValueKey(name),
                tween: Tween(begin: 0, end: hp),
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOutCubic,
                builder: (context, shown, _) => Stack(
                  children: [
                    Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: shown.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF4FD8), Color(0xFFFF3B5C)],
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    // Pips: as viradas de fase em 60% e 30% da vida.
                    for (final f in const [0.6, 0.3])
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment((f * 2) - 1, 0),
                          child: Container(width: 2, color: Colors.black54),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tally de fim de estágio: os bônus contando UM A UM. O momento mais
/// dopaminérgico do gênero — agora existe.
class _StageTally extends StatelessWidget {
  const _StageTally({required this.game});

  final DanmakuGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.stageClearNotifier,
      builder: (context, data, _) {
        if (data == null) return const SizedBox.shrink();
        return _TallyCard(
          key: ValueKey(data),
          data: data,
          onDone: () => game.stageClearNotifier.value = null,
        );
      },
    );
  }
}

class _TallyCard extends StatefulWidget {
  const _TallyCard({super.key, required this.data, required this.onDone});

  final ({int stage, int noMiss, int graze, int medal}) data;
  final VoidCallback onDone;

  @override
  State<_TallyCard> createState() => _TallyCardState();
}

class _TallyCardState extends State<_TallyCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int _lastStep = -1;

  static const _steps = [0.16, 0.34, 0.52, 0.74]; // linhas + total

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )
      ..addListener(_tickSounds)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  void _tickSounds() {
    for (var i = 0; i < _steps.length; i++) {
      if (_c.value >= _steps[i] && _lastStep < i) {
        _lastStep = i;
        i == _steps.length - 1
            ? sfx.play('stageclear', volume: 0.8)
            : sfx.play('tick', volume: 0.6);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final total = d.noMiss + d.graze + d.medal;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final opacity = t < 0.08
              ? t / 0.08
              : t > 0.9
                  ? (1 - t) / 0.1
                  : 1.0;
          Widget row(String label, int value, double at, {Color? color}) {
            final on = t >= at;
            return AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 108,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 82,
                      child: Text(
                        value > 0 ? '+$value' : '—',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: color ??
                              (value > 0
                                  ? const Color(0xFFFFD23F)
                                  : Colors.white24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // No alto e translúcido: o tally comemora sem esconder bala.
          return Align(
            alignment: const Alignment(0, -0.68),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0618).withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF35E1F5).withValues(alpha: 0.7),
                      width: 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SETOR ${d.stage} LIMPO',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Color(0xFF35E1F5), blurRadius: 10),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    row('SEM DANO', d.noMiss, _steps[0]),
                    row('GRAZE', d.graze, _steps[1]),
                    row('MEDALHAS', d.medal, _steps[2]),
                    const SizedBox(height: 3),
                    row('TOTAL', total, _steps[3],
                        color: const Color(0xFF4BF07A)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Medidor de poder da arma: uma casa por nível, a atual preenchendo.
///
/// É o painel de progressão sempre à vista — o jogador precisa ver o quanto
/// falta para o próximo upgrade, senão a subida não puxa.
class _PowerMeter extends StatelessWidget {
  const _PowerMeter({required this.game});

  final DanmakuGame game;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Etiqueta com o nome/cor da arma equipada.
        ValueListenableBuilder(
          valueListenable: game.weaponTypeNotifier,
          builder: (context, type, _) => Text(
            type.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: type.color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder(
          valueListenable: game.weaponLevelNotifier,
          builder: (context, level, _) => ValueListenableBuilder(
            valueListenable: game.powerFillNotifier,
            builder: (context, fill, _) => Row(
              children: [
                for (var i = 0; i < kMaxWeaponLevel; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: _PowerPip(
                      // casa cheia, parcial (nível atual) ou vazia
                      fill: i < level - 1
                          ? 1.0
                          : i == level - 1
                              ? (level >= kMaxWeaponLevel ? 1.0 : fill)
                              : 0.0,
                      maxed: level >= kMaxWeaponLevel,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  level >= kMaxWeaponLevel ? 'MÁX' : 'Lv.$level',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: level >= kMaxWeaponLevel
                        ? const Color(0xFFFF4FD8)
                        : const Color(0xFF35E1F5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PowerPip extends StatelessWidget {
  const _PowerPip({required this.fill, required this.maxed});

  final double fill;
  final bool maxed;

  @override
  Widget build(BuildContext context) {
    final color = maxed ? const Color(0xFFFF4FD8) : const Color(0xFF35E1F5);
    return Container(
      width: 22,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(2),
        boxShadow: maxed
            ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
            : null,
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fill.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Telemetria discreta — ainda medindo performance, mas fora do caminho.
class _Telemetry extends StatelessWidget {
  const _Telemetry({required this.game});

  final DanmakuGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.fpsNotifier,
      builder: (context, fps, _) {
        final color = fps >= 55
            ? Colors.white38
            : fps >= 42
                ? const Color(0xFFFFD23F)
                : const Color(0xFFFF3B5C);
        return Text(
          '${fps.round()} fps',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        );
      },
    );
  }
}

// ── Bomba ────────────────────────────────────────────────────────────────

class _BombButton extends StatelessWidget {
  const _BombButton({required this.game, this.paused = false});

  final DanmakuGame game;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: game.bombsNotifier,
      builder: (context, bombs, _) {
        final enabled = bombs > 0 && !paused;
        return GestureDetector(
          onTap: enabled ? game.useBomb : null,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? const Color(0xFF35E1F5).withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: enabled ? const Color(0xFF35E1F5) : Colors.white24,
                width: 2,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFF35E1F5).withValues(alpha: 0.35),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.blur_on_rounded,
                  color: enabled ? const Color(0xFF35E1F5) : Colors.white24,
                  size: 28,
                ),
                Text(
                  '$bombs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: enabled ? Colors.white : Colors.white24,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Intro de fase ────────────────────────────────────────────────────────

class _StageIntro extends StatefulWidget {
  const _StageIntro({required this.difficulty});

  final Difficulty difficulty;

  @override
  State<_StageIntro> createState() => _StageIntroState();
}

class _StageIntroState extends State<_StageIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          if (t >= 1.0) return const SizedBox.shrink();
          // Aparece, segura, e some no fim.
          final opacity = t < 0.15
              ? t / 0.15
              : t > 0.8
                  ? (1 - t) / 0.2
                  : 1.0;
          final label = t < 0.62
              ? difficultyConfigs[widget.difficulty]!.label.toUpperCase()
              : 'PREPARE-SE';
          const cyan = Color(0xFF35E1F5);
          final a = opacity.clamp(0.0, 1.0);
          final h = MediaQuery.of(context).size.height * (68 / 1280);
          // MESMA faixa dos anúncios do jogo (AnnounceBanner), em ciano.
          return Align(
            alignment: const Alignment(0, -0.69),
            child: Container(
              height: h,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF120514).withValues(alpha: 0.42 * a),
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: cyan.withValues(alpha: 0.5 * a),
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  color: Colors.white.withValues(alpha: 0.92 * a),
                  shadows: [
                    Shadow(
                      color: cyan.withValues(alpha: 0.6 * a),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Fim de jogo ──────────────────────────────────────────────────────────

class _GameOver extends StatelessWidget {
  const _GameOver({
    required this.result,
    required this.newRecord,
    required this.difficulty,
    required this.creditsEarned,
    required this.onRestart,
    required this.onMenu,
    this.creditsDoubled = false,
    this.daily = false,
    this.onRevive,
    this.onDoubleCredits,
  });

  final ({int score, int graze, int wave}) result;
  final bool newRecord;
  final Difficulty difficulty;
  final int creditsEarned;
  final bool creditsDoubled;
  final bool daily;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  /// Recompensas por anúncio (null = indisponível/já usada → botão some).
  final VoidCallback? onRevive;
  final VoidCallback? onDoubleCredits;

  @override
  Widget build(BuildContext context) {
    final cfg = difficultyConfigs[difficulty]!;

    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ABATIDO',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: Color(0xFFFF3B5C),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              daily ? 'DESAFIO DIÁRIO' : cfg.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '${result.score}',
              style: const TextStyle(
                fontSize: 54,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
              ),
            ),
            if (newRecord)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD23F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'NOVO RECORDE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: Color(0xFF05030F),
                  ),
                ),
              )
            // "Faltaram X" — o gatilho de "só mais uma" mais barato que há.
            else if (highScores.of(difficulty) > result.score)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'faltaram ${highScores.of(difficulty) - result.score} pts '
                  'para o recorde',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFF8A3D),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Stat(label: 'GRAZE', value: '${result.graze}'),
                const SizedBox(width: 34),
                _Stat(label: 'ONDAS', value: '${result.wave}'),
                const SizedBox(width: 34),
                _Stat(label: 'RECORDE', value: '${highScores.of(difficulty)}'),
              ],
            ),
            if (creditsEarned > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD23F).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color:
                              const Color(0xFFFFD23F).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.paid_rounded,
                            color: Color(0xFFFFD23F), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          creditsDoubled
                              ? '+$creditsEarned créditos ×2!'
                              : '+$creditsEarned créditos',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFFD23F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Dobrar créditos assistindo um anúncio (opt-in).
                  if (onDoubleCredits != null)
                    ValueListenableBuilder(
                      valueListenable: ads.rewardedReady,
                      builder: (context, ready, _) => !ready
                          ? const SizedBox.shrink()
                          : GestureDetector(
                              onTap: onDoubleCredits,
                              child: Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD23F),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.slow_motion_video_rounded,
                                        size: 16, color: Color(0xFF05030F)),
                                    SizedBox(width: 4),
                                    Text(
                                      '×2',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF05030F),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 34),
            // CONTINUAR por anúncio: a run não acabou se você não quiser.
            if (onRevive != null)
              ValueListenableBuilder(
                valueListenable: ads.rewardedReady,
                builder: (context, ready, _) => !ready
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        onTap: onRevive,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 34, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4BF07A),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4BF07A)
                                    .withValues(alpha: 0.4),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: const Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_circle_fill_rounded,
                                      size: 20, color: Color(0xFF05030F)),
                                  SizedBox(width: 8),
                                  Text(
                                    'CONTINUAR',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                      color: Color(0xFF05030F),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'assista um anúncio · +2 naves · 1× por partida',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF05030F),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            if (daily)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Uma tentativa por dia. Volte amanhã.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white54,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: onRestart,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF35E1F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'DE NOVO',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFF05030F),
                    ),
                  ),
                ),
              ),
            GestureDetector(
              onTap: onMenu,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                child: const Text(
                  'MENU',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Colors.white38,
          ),
        ),
      ],
    );
  }
}
