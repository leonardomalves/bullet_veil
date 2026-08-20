/// Níveis de dificuldade selecionáveis na tela de título.
///
/// Cada eixo mexe numa alavanca diferente: velocidade de bala (reação),
/// HP inimigo (duração da luta), densidade (leitura de tela) e recompensa
/// (pontos e vidas). Jogar mais difícil vale mais pontos — a troca clássica
/// risco ↔ recompensa que dá motivo para subir de nível.
enum Difficulty { easy, normal, hard, insane }

class DifficultyConfig {
  const DifficultyConfig({
    required this.label,
    required this.subtitle,
    required this.speedBase,
    required this.speedMax,
    required this.rampWaves,
    required this.hpMul,
    required this.scoreMul,
    required this.oneUpEvery,
    required this.oneUpDropChance,
    required this.startBombs,
    required this.densityDelta,
    required this.waveCdBonus,
    required this.rankGainMul,
    required this.rankMaxExtraEnemies,
    required this.rankSpeedBonus,
  });

  final String label;
  final String subtitle;

  /// Escala de velocidade das balas no início e no teto da rampa.
  final double speedBase;
  final double speedMax;

  /// Em quantas ondas a rampa satura.
  final int rampWaves;

  final double hpMul;
  final double scoreMul;

  /// Marco de pontuação para 1UP e chance de nave cair de inimigo comum.
  final int oneUpEvery;
  final double oneUpDropChance;

  final int startBombs;

  /// Somado à contagem de balas dos padrões densos (anel/parede/chefe).
  final int densityDelta;

  /// Folga extra entre ondas.
  final double waveCdBonus;

  /// Rank ("Fúria"): o jogo responde ao poder do jogador. Quanto mais forte
  /// e agressivo, mais rápido a fúria sobe; morrer a derruba. Ela controla
  /// velocidade de bala, HP inimigo e QUANTAS naves extras entram — a alma
  /// da dificuldade dinâmica dos clássicos.
  final double rankGainMul; // multiplicador de tudo que sobe a fúria
  final double rankMaxExtraEnemies; // naves extras por onda com fúria cheia
  final double rankSpeedBonus; // + na velocidade de bala com fúria cheia
}

const difficultyConfigs = <Difficulty, DifficultyConfig>{
  Difficulty.easy: DifficultyConfig(
    label: 'RECRUTA',
    subtitle: 'Balas lentas, tela limpa, muitas naves',
    speedBase: 0.52,
    speedMax: 0.78,
    rampWaves: 22,
    hpMul: 0.85,
    scoreMul: 0.7,
    oneUpEvery: 3500,
    oneUpDropChance: 0.030,
    startBombs: 3,
    densityDelta: -2,
    waveCdBonus: 0.5,
    rankGainMul: 0.6,
    rankMaxExtraEnemies: 2,
    rankSpeedBonus: 0.16,
  ),
  Difficulty.normal: DifficultyConfig(
    label: 'PILOTO',
    subtitle: 'A fúria responde ao seu poder',
    speedBase: 0.64,
    speedMax: 1.0,
    rampWaves: 16,
    hpMul: 1.05,
    scoreMul: 1.0,
    oneUpEvery: 4500,
    oneUpDropChance: 0.016,
    startBombs: 2,
    densityDelta: 0,
    waveCdBonus: 0.0,
    rankGainMul: 1.0,
    rankMaxExtraEnemies: 3,
    rankSpeedBonus: 0.24,
  ),
  Difficulty.hard: DifficultyConfig(
    label: 'VETERANO',
    subtitle: 'Rápido, denso, pontos ×1.5',
    speedBase: 0.76,
    speedMax: 1.14,
    rampWaves: 11,
    hpMul: 1.35,
    scoreMul: 1.5,
    oneUpEvery: 5500,
    oneUpDropChance: 0.011,
    startBombs: 2,
    densityDelta: 3,
    waveCdBonus: -0.5,
    rankGainMul: 1.35,
    rankMaxExtraEnemies: 4,
    rankSpeedBonus: 0.30,
  ),
  Difficulty.insane: DifficultyConfig(
    label: 'LENDA',
    subtitle: 'Sem perdão. Glória máxima',
    speedBase: 0.9,
    speedMax: 1.3,
    rampWaves: 8,
    hpMul: 1.7,
    scoreMul: 2.0,
    oneUpEvery: 6500,
    oneUpDropChance: 0.007,
    startBombs: 1,
    densityDelta: 6,
    waveCdBonus: -0.9,
    rankGainMul: 1.7,
    rankMaxExtraEnemies: 6,
    rankSpeedBonus: 0.38,
  ),
};
