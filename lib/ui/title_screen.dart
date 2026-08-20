import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/achievements.dart';
import '../core/daily.dart';
import '../core/high_scores.dart';
import '../core/garage.dart';
import '../core/missions.dart';
import '../core/settings.dart';
import '../core/stats.dart';
import '../game/difficulty.dart';
import 'hangar_screen.dart';
import 'game_screen.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _play(Difficulty d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(difficulty: d)),
    );
    // Voltou do jogo: recordes podem ter mudado.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05030F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B0620), Color(0xFF05030F)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              children: [
                const SizedBox(height: 30),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final glow =
                        0.5 + 0.5 * math.sin(_pulse.value * math.pi * 2);
                    return Column(
                      children: [
                        Text(
                          'BULLET',
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 12,
                            height: 1,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: const Color(0xFF35E1F5)
                                    .withValues(alpha: 0.5 + 0.4 * glow),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'VEIL',
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 26,
                            height: 1.1,
                            color: const Color(0xFF35E1F5),
                            shadows: [
                              Shadow(
                                color: const Color(0xFF35E1F5)
                                    .withValues(alpha: 0.4 + 0.5 * glow),
                                blurRadius: 30,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                const Text(
                  'Escolha sua provação',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white38,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 22),
                for (final d in Difficulty.values) ...[
                  _DifficultyCard(
                    difficulty: d,
                    // LENDA fica trancada até derrubar um chefe no VETERANO.
                    locked: d == Difficulty.insane &&
                        !settings.legendUnlocked &&
                        highScores.of(d) == 0,
                    onTap: () => _play(d),
                  ),
                  const SizedBox(height: 12),
                ],
                _DailyCard(onChanged: () => setState(() {})),
                const SizedBox(height: 12),
                const _MissionsPanel(),
                const SizedBox(height: 12),
                // HANGAR: monta a nave (skins + módulos) com os créditos.
                GestureDetector(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HangarScreen()),
                    );
                    if (context.mounted) {
                      (context as Element).markNeedsBuild();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF35E1F5).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF35E1F5).withValues(alpha: 0.6),
                          width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.build_circle_rounded,
                            color: Color(0xFF35E1F5), size: 20),
                        const SizedBox(width: 8),
                        AnimatedBuilder(
                          animation: garage,
                          builder: (context, _) => Text(
                            'HANGAR  ·  ${garage.credits} créditos',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: Color(0xFF35E1F5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _SmallButton(
                        icon: Icons.military_tech_rounded,
                        color: const Color(0xFFFFD23F),
                        label:
                            'MEDALHAS ${achievements.unlockedCount}/${achievements.total}',
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: const Color(0xFF0B0620),
                          showDragHandle: true,
                          builder: (_) => const _AchievementsSheet(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SmallButton(
                        icon: Icons.query_stats_rounded,
                        color: const Color(0xFF4BF07A),
                        label: 'ESTATÍSTICAS',
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: const Color(0xFF0B0620),
                          showDragHandle: true,
                          builder: (_) => const _StatsSheet(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Arraste para voar · O ponto branco é você',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white24,
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.difficulty,
    required this.onTap,
    this.locked = false,
  });

  final Difficulty difficulty;
  final VoidCallback onTap;
  final bool locked;

  static const _accents = {
    Difficulty.easy: Color(0xFF4BF07A),
    Difficulty.normal: Color(0xFF35E1F5),
    Difficulty.hard: Color(0xFFFF8A3D),
    Difficulty.insane: Color(0xFFFF3B5C),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = difficultyConfigs[difficulty]!;
    final accent = locked ? Colors.white24 : _accents[difficulty]!;
    final best = highScores.of(difficulty);

    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Row(
          children: [
            if (locked) ...[
              const Icon(Icons.lock_rounded, color: Colors.white24, size: 22),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cfg.label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    locked
                        ? 'Derrote um chefe no VETERANO para abrir'
                        : cfg.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            if (!locked)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PONTOS ×${cfg.scoreMul.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    best > 0 ? 'RECORDE $best' : '— sem recorde —',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: best > 0
                          ? const Color(0xFFFFD23F)
                          : Colors.white24,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Desafio diário: mesma seed pro dia todo, UMA tentativa.
class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.onChanged});

  final VoidCallback onChanged;

  static const _purple = Color(0xFF9B4DFF);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: daily,
      builder: (context, _) {
        final played = daily.playedToday;
        return GestureDetector(
          onTap: played
              ? null
              : () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GameScreen(daily: true),
                    ),
                  );
                  onChanged();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: played ? 0.04 : 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _purple.withValues(alpha: played ? 0.3 : 0.7),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.today_rounded,
                    color: played ? Colors.white24 : _purple, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DESAFIO DIÁRIO',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: played ? Colors.white38 : _purple,
                        ),
                      ),
                      Text(
                        played
                            ? 'Hoje: ${daily.todayScore} pts · volte amanhã'
                            : 'As mesmas ondas para todos · 1 tentativa',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (daily.bestEver > 0)
                  Text(
                    'MELHOR\n${daily.bestEver}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFFD23F),
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

/// As 3 missões de hoje, com barra de progresso — metas de sessão.
class _MissionsPanel extends StatelessWidget {
  const _MissionsPanel();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: missions,
      builder: (context, _) {
        if (missions.today.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MISSÕES DE HOJE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Color(0xFF4BF07A),
                ),
              ),
              const SizedBox(height: 8),
              for (final m in missions.today) ...[
                Row(
                  children: [
                    Icon(
                      m.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: m.done ? const Color(0xFF4BF07A) : Colors.white24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.def.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: m.done ? Colors.white38 : Colors.white70,
                          decoration: m.done ? TextDecoration.lineThrough : null,
                          decorationColor: Colors.white38,
                        ),
                      ),
                    ),
                    Text(
                      m.done
                          ? '+${m.def.reward}¢'
                          : '${m.progress}/${m.def.target}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: m.done
                            ? const Color(0xFFFFD23F)
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 23),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: m.fraction,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF4BF07A),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estatísticas de carreira + sparkline das últimas 10 runs.
class _StatsSheet extends StatelessWidget {
  const _StatsSheet();

  String _fmtTime(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Column(
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
                letterSpacing: 1.2,
                color: Colors.white38,
              ),
            ),
          ],
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ESTATÍSTICAS DE CARREIRA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Color(0xFF4BF07A),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                stat('ABATES', '${stats.totalKills}'),
                stat('PARTIDAS', '${stats.totalRuns}'),
                stat('MELHOR ONDA', '${stats.bestWave}'),
                stat('TEMPO', _fmtTime(stats.totalSeconds)),
              ],
            ),
            const SizedBox(height: 24),
            if (stats.history.length >= 2) ...[
              const Text(
                'ÚLTIMAS PARTIDAS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 70,
                width: double.infinity,
                child: CustomPaint(painter: _SparklinePainter(stats.history)),
              ),
            ] else
              const Text(
                'Jogue algumas partidas para ver sua curva.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white38,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce(math.max).toDouble().clamp(1, double.infinity);
    final dx = size.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(i * dx, size.height - (values[i] / maxV) * size.height * 0.92),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF35E1F5),
    );
    for (final p in points) {
      canvas.drawCircle(p, 3, Paint()..color = const Color(0xFF35E1F5));
    }
    // A última run em destaque: dourada.
    canvas.drawCircle(points.last, 4.5, Paint()..color = const Color(0xFFFFD23F));
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

class _AchievementsSheet extends StatelessWidget {
  const _AchievementsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        shrinkWrap: true,
        children: [
          Text(
            'CONDECORAÇÕES ${achievements.unlockedCount}/${achievements.total}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Color(0xFFFFD23F),
            ),
          ),
          const SizedBox(height: 14),
          for (final a in Achievement.values)
            _AchievementRow(a: a, unlocked: achievements.isUnlocked(a)),
        ],
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.a, required this.unlocked});

  final Achievement a;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: unlocked
            ? const Color(0xFFFFD23F).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked
              ? const Color(0xFFFFD23F).withValues(alpha: 0.5)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.military_tech_rounded : Icons.lock_rounded,
            color: unlocked ? const Color(0xFFFFD23F) : Colors.white24,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: unlocked ? Colors.white : Colors.white38,
                  ),
                ),
                Text(
                  a.description,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
