import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/game/difficulty.dart';
import 'package:bullet_veil/game/enemy.dart';

/// Folha de contato dos inimigos.
///
/// `Enemy.render` só lê raio/cor/isBoss/flash/spin — nada do jogo montado — o
/// que deixa desenhá-los isolados. Prova visual de que agora são NAVES (e o
/// chefe uma fortaleza), sem nenhuma estrela de 6 pontas.
void main() {
  test('gera folha de contato dos inimigos', () async {
    final kit = EnemyFactory(difficultyConfigs[Difficulty.normal]!);
    final enemies = <(String, Enemy)>[
      ('grunt', kit.grunt(0)),
      ('easyGrunt', kit.easyGrunt(0, colorIndex: 4)),
      ('spinner', kit.spinner(0)),
      ('ringer', kit.ringer(0)),
      ('runner', kit.runner(0, true)),
      ('heavy', kit.heavy(0)),
      ('boss:dreadnought', kit.boss(1)),
      ('boss:mantis', kit.boss(2)),
      ('boss:core', kit.boss(3)),
    ];

    const cell = 190.0;
    const cols = 4;
    final rows = (enemies.length + cols - 1) ~/ cols;
    final width = (cell * cols).toInt();
    final height = (cell * rows).toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF05030F),
    );

    for (var i = 0; i < enemies.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      canvas.save();
      canvas.translate(col * cell + cell / 2, row * cell + cell / 2);
      enemies[i].$2.render(canvas);
      canvas.restore();
    }

    final image =
        await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final out = File('build/enemy_preview.png');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    expect(await out.length(), greaterThan(0));

    // Sanidade: os arquétipos têm raios coerentes (chefe é o maior).
    expect(enemies.last.$2.isBoss, isTrue);
    expect(enemies.last.$2.radius, greaterThan(enemies.first.$2.radius));
  });
}
