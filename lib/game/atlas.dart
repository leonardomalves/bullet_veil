import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum BulletShape { orb, rice, dart, bigOrb, laser }

/// Paleta das balas. Cores saturadas sobre fundo escuro, porque a leitura da
/// tela é a mecânica principal: o jogador precisa distinguir tipos de bala num
/// relance para saber o que vai acontecer.
const bulletColors = <Color>[
  Color(0xFFFF3B5C), // vermelho
  Color(0xFFFF4FD8), // magenta
  Color(0xFF4C6BFF), // azul
  Color(0xFF35E1F5), // ciano
  Color(0xFF4BF07A), // verde
  Color(0xFFFFD23F), // amarelo
  Color(0xFFFFFFFF), // branco
  Color(0xFFFF8A3D), // laranja
];

/// Atlas de sprites das balas, desenhado em runtime numa `ui.Image`.
///
/// Existe por um motivo de performance, não de estética: com um atlas único
/// todas as balas do frame saem em **uma** chamada `drawRawAtlas`, que a GPU
/// resolve em lote. Um componente por bala com gradiente próprio — a
/// abordagem que funciona para 40 frutas — derreteria aqui a 2000 balas.
class BulletAtlas {
  BulletAtlas._(this.image, this._rects);

  static const double cell = 64;
  static const int cols = 8; // uma coluna por cor

  final ui.Image image;
  final List<Rect> _rects;

  Rect rectAt(int index) => _rects[index];

  /// Índice no atlas para uma combinação forma+cor.
  static int id(BulletShape shape, int color) => shape.index * cols + color;

  static Future<BulletAtlas> generate() async {
    final rows = BulletShape.values.length;
    final width = (cols * cell).toInt();
    final height = (rows * cell).toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rects = <Rect>[];

    for (final shape in BulletShape.values) {
      for (var c = 0; c < cols; c++) {
        final left = c * cell;
        final top = shape.index * cell;
        rects.add(Rect.fromLTWH(left, top, cell, cell));

        canvas.save();
        canvas.translate(left + cell / 2, top + cell / 2);
        _paintBullet(canvas, shape, bulletColors[c]);
        canvas.restore();
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    return BulletAtlas._(image, rects);
  }

  /// Desenha uma bala centrada na origem, apontando para -Y.
  ///
  /// Toda bala tem halo colorido + corpo + núcleo claro. Esse núcleo não é
  /// enfeite: ele marca visualmente o centro real da colisão.
  static void _paintBullet(Canvas canvas, BulletShape shape, Color color) {
    final glow = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final body = Paint()..color = color;
    final core = Paint()..color = Colors.white.withValues(alpha: 0.95);

    switch (shape) {
      case BulletShape.orb:
        canvas.drawCircle(Offset.zero, 11, glow);
        canvas.drawCircle(Offset.zero, 8.5, body);
        canvas.drawCircle(Offset.zero, 4.2, core);

      case BulletShape.bigOrb:
        canvas.drawCircle(Offset.zero, 22, glow);
        canvas.drawCircle(Offset.zero, 17, body);
        canvas.drawCircle(Offset.zero, 8.5, core);

      case BulletShape.rice:
        final r = Rect.fromCenter(center: Offset.zero, width: 11, height: 22);
        canvas.drawOval(r.inflate(3), glow);
        canvas.drawOval(r, body);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 4.5, height: 11),
          core,
        );

      case BulletShape.dart:
        final path = Path()
          ..moveTo(0, -16)
          ..lineTo(8.5, 10)
          ..lineTo(0, 5)
          ..lineTo(-8.5, 10)
          ..close();
        canvas.drawPath(path, glow);
        canvas.drawPath(path, body);
        canvas.drawPath(
          Path()
            ..moveTo(0, -9)
            ..lineTo(3.4, 5)
            ..lineTo(-3.4, 5)
            ..close(),
          core,
        );

      case BulletShape.laser:
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 9, height: 56),
          const Radius.circular(4.5),
        );
        canvas.drawRRect(r.inflate(3), glow);
        canvas.drawRRect(r, body);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 3.4, height: 50),
            const Radius.circular(1.7),
          ),
          core,
        );
    }
  }

  /// Raio de colisão de cada forma. Sempre MENOR que o desenho — a regra não
  /// escrita do gênero: se a morte parece injusta o jogador culpa o jogo, não
  /// a si mesmo. Hitbox generoso a favor do jogador é design, não bug.
  static double hitRadiusOf(BulletShape shape) => switch (shape) {
        BulletShape.orb => 6.0,
        BulletShape.bigOrb => 13.0,
        BulletShape.rice => 5.0,
        BulletShape.dart => 5.5,
        BulletShape.laser => 4.5,
      };

  void dispose() => image.dispose();
}

/// Converte rotação/escala/translação nos 4 floats que `drawRawAtlas` espera,
/// já compensando a âncora no centro da célula.
void writeRSTransform(
  Float32List out,
  int slot,
  double rotation,
  double scale,
  double anchorX,
  double anchorY,
  double translateX,
  double translateY,
) {
  final scos = math.cos(rotation) * scale;
  final ssin = math.sin(rotation) * scale;
  final i = slot * 4;
  out[i] = scos;
  out[i + 1] = ssin;
  out[i + 2] = translateX - scos * anchorX + ssin * anchorY;
  out[i + 3] = translateY - ssin * anchorX - scos * anchorY;
}
