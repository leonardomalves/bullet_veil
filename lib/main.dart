import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/achievements.dart';
import 'core/ads.dart';
import 'core/daily.dart';
import 'core/garage.dart';
import 'core/haptics.dart';
import 'core/high_scores.dart';
import 'core/missions.dart';
import 'core/settings.dart';
import 'core/sfx.dart';
import 'core/stats.dart';
import 'game/sprites.dart';
import 'ui/game_screen.dart';
import 'ui/hangar_screen.dart';
import 'ui/title_screen.dart';

/// Atalho de dev para inspecionar telas sem navegar:
///   `--dart-define=BOOT=hangar`  abre o hangar
///   `--dart-define=BOOT=game`    cai direto numa partida (PILOTO)
const _boot = String.fromEnvironment('BOOT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await highScores.load();
  await garage.load();
  await achievements.load(); // depois do garage: desbloqueio paga créditos
  await haptics.load();
  await settings.load();
  await missions.load();
  await stats.load();
  await daily.load();
  await sprites.load(); // arte 3D pre-renderizada; ausente = volta ao vetor
  await sfx.init(); // degrada para silêncio se o dispositivo não colaborar
  ads.init(); // sem await: rede não atrasa o boot; sem fill = botões somem
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Flame.device.fullScreen();
  runApp(const BulletVeilApp());
}

class BulletVeilApp extends StatelessWidget {
  const BulletVeilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bullet Veil',
      debugShowCheckedModeBanner: false,
      home: switch (_boot) {
        'hangar' => const HangarScreen(),
        'game' => const GameScreen(),
        _ => const TitleScreen(),
      },
    );
  }
}
