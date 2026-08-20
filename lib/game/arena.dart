/// Resolução virtual fixa; a câmera faz o letterbox.
const double kArenaWidth = 720;
const double kArenaHeight = 1280;

/// Margem em que as balas são descartadas. Generosa de propósito: bala que
/// some na borda visível denuncia o truque e atrapalha a leitura do padrão.
const double kCullMargin = 90;

/// Hitbox do jogador. Minúsculo — é a regra de ouro do gênero: a nave é
/// grande para ser vista, o ponto vulnerável é quase um pixel.
const double kPlayerHitRadius = 5;

/// Raio de graze: passar dentro dele sem morrer pontua. É o que transforma
/// medo em ganância, e é o principal gancho do bullet hell.
const double kGrazeRadius = 28;

/// Invulnerabilidade após tomar dano.
const double kInvulnDuration = 2.0;

/// Teto do pool de balas inimigas. Acima disso o spawn é ignorado, então o
/// jogo degrada em densidade em vez de em framerate.
const int kEnemyBulletCap = 3000;
const int kPlayerBulletCap = 400;

/// Limites de movimento da nave.
const double kPlayerMinX = 18;
const double kPlayerMaxX = kArenaWidth - 18;
const double kPlayerMinY = 90;
const double kPlayerMaxY = kArenaHeight - 40;

/// Progressão de arma. Nível 1 é de propósito fraquíssimo — a subida é o
/// gancho, e ela só tem graça se o começo pedir a evolução.
const int kMaxWeaponLevel = 6;

/// Coleta de power-ups: o item é atraído para a nave dentro do raio de ímã
/// (a "sucção" que dá gosto) e coletado dentro do raio menor.
const double kPickupMagnetRadius = 155;
const double kPickupCollectRadius = 34;
const double kPickupDriftSpeed = 82;

/// Naves (vidas). Começa com 3, ganha por marco de pontuação e do chefe.
const int kStartLives = 3;
const int kMaxLives = 6;
const int kMaxBombs = 5;

/// Marco de pontuação para ganhar uma nave. Baixo de propósito: o jogador
/// precisa sentir que ganha vida DURANTE a luta, não só num número distante.
const int kOneUpEvery = 4500;

/// Escada da cadeia de medalhas: o valor sobe a cada coleta em sequência e
/// zera se uma cair. São OITO degraus porque a escada sonora tem oito amostras
/// (`medal_1..medal_8`) — mexer no tamanho aqui exige mexer no áudio.
///
/// O topo é deliberadamente modesto: o valor ainda é multiplicado pela cadeia
/// (até ×4) e pela dificuldade (até ×2), então 2500 no topo já vale 20 mil por
/// medalha no LENDA. Com o topo antigo de 10 mil, a colheita de um chefe (14
/// medalhas) sozinha valia mais de um milhão, e era o que estourava o placar.
const List<int> kMedalSteps = [50, 100, 200, 350, 600, 1000, 1600, 2500];

/// Versão do cliente carimbada nos replays (manter em dia com o pubspec).
const String kClientVersion = '1.4.1+2006';
