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
import 'ui/hangar_screen.dart';
import 'ui/title_screen.dart';

/// Atalho de dev para inspecionar telas: `--dart-define=BOOT=hangar`.
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
      home: _boot == 'hangar' ? const HangarScreen() : const TitleScreen(),
    );
  }
}
