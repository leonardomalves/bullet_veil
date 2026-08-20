import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/garage.dart';

/// Ícones dos módulos do hangar, desenhados em vetor.
///
/// Vieram do canvas do Claude Design como SVG e foram traduzidos para `Path`
/// em vez de virarem PNG: o hangar inteiro já desenha assim, então não custam
/// asset, não custam entrada no `pubspec` e não borram em tela nenhuma.
///
/// Cada módulo tem cor própria — é o que faz os quatro se distinguirem num
/// relance na lista da loja. Sem posse, o desenho perde a cor mas mantém a
/// silhueta: dá para saber o que se está comprando antes de comprar.
class ModuleIcon extends StatelessWidget {
  const ModuleIcon(this.module, {super.key, this.size = 26, this.owned = true});

  final ShipModule module;
  final double size;
  final bool owned;

  /// Cor de identidade de cada módulo, casada com a paleta das balas.
  static Color accentOf(ShipModule m) => switch (m) {
        ShipModule.missilePod => const Color(0xFFFF4FD8),
        ShipModule.wingmen => const Color(0xFF4BF07A),
        ShipModule.shield => const Color(0xFF35E1F5),
        ShipModule.overdrive => const Color(0xFFFFD23F),
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ModuleIconPainter(module, owned)),
    );
  }
}

class _ModuleIconPainter extends CustomPainter {
  _ModuleIconPainter(this.module, this.owned);

  final ShipModule module;
  final bool owned;

  /// O SVG de origem usa `viewBox="4 4 56 56"`.
  static const _origin = 4.0;
  static const _extent = 56.0;

  /// Espessura de contorno do SVG (`--ow`), no espaço do viewBox.
  static const _ow = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    final accent =
        owned ? ModuleIcon.accentOf(module) : Colors.white.withValues(alpha: 0.22);
    final line = owned ? Colors.white : Colors.white.withValues(alpha: 0.30);

    canvas.save();
    final k = size.width / _extent;
    canvas.scale(k);
    canvas.translate(-_origin, -_origin);

    final fill = Paint()..color = accent;
    Paint stroke([double w = _ow]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = line;

    switch (module) {
      case ShipModule.missilePod:
        _missilePod(canvas, fill, stroke);
      case ShipModule.wingmen:
        _wingmen(canvas, fill, stroke);
      case ShipModule.shield:
        _shield(canvas, fill, stroke, line);
      case ShipModule.overdrive:
        _overdrive(canvas, fill, stroke);
    }

    canvas.restore();
  }

  /// Bloco lançador com três tubos e um míssil saindo em curva.
  void _missilePod(Canvas canvas, Paint fill, Paint Function([double]) stroke) {
    canvas.drawPath(
      Path()
        ..moveTo(40, 26.5)
        ..cubicTo(47.5, 25, 50, 20.5, 50, 15.5),
      stroke(),
    );

    canvas.save();
    canvas.translate(49.5, 16);
    canvas.rotate(35 * math.pi / 180);
    final missile = Path()
      ..moveTo(0, -11)
      ..lineTo(3.3, -4.5)
      ..lineTo(3.3, 6.5)
      ..lineTo(-3.3, 6.5)
      ..lineTo(-3.3, -4.5)
      ..close();
    canvas
      ..drawPath(missile, fill)
      ..drawPath(missile, stroke());
    canvas.restore();

    for (final top in const [22.5, 34.3, 46.1]) {
      final tube = RRect.fromRectAndRadius(
        Rect.fromLTWH(24, top, 16, 7.4),
        const Radius.circular(3.7),
      );
      canvas
        ..drawRRect(tube, fill)
        ..drawRRect(tube, stroke());
    }

    final block = RRect.fromRectAndRadius(
      Rect.fromLTWH(7, 19.5, 20, 37),
      const Radius.circular(3.5),
    );
    canvas
      ..drawRRect(block, fill)
      ..drawRRect(block, stroke());

    // Bocas dos tubos: buraco na cor do fundo do jogo.
    final bore = Paint()..color = const Color(0xFF05030F);
    for (final cy in const [26.2, 38.0, 49.8]) {
      canvas.drawCircle(Offset(36.4, cy), 2.4, bore);
    }
  }

  /// Caça central ladeado por dois drones menores, em V.
  void _wingmen(Canvas canvas, Paint fill, Paint Function([double]) stroke) {
    Path dart() => Path()
      ..moveTo(0, -15)
      ..lineTo(12.5, 9)
      ..lineTo(0, 3.5)
      ..lineTo(-12.5, 9)
      ..close();

    // (dx, dy, escala, contorno) — o contorno é escalado junto, como no SVG,
    // então os três terminam com a mesma espessura óptica.
    for (final s in const [
      (15.0, 43.0, 0.62, 4.2),
      (49.0, 43.0, 0.62, 4.2),
      (32.0, 22.0, 1.08, 2.4),
    ]) {
      canvas.save();
      canvas.translate(s.$1, s.$2);
      canvas.scale(s.$3);
      final d = dart();
      canvas
        ..drawPath(d, fill)
        ..drawPath(d, stroke(s.$4));
      canvas.restore();
    }
  }

  /// Escudo hexagonal com faceta interna e uma quebra de luz na borda.
  void _shield(Canvas canvas, Paint fill, Paint Function([double]) stroke,
      Color line) {
    canvas.drawPath(
      Path()
        ..moveTo(32, 5)
        ..lineTo(52, 17)
        ..lineTo(52, 41)
        ..lineTo(32, 53)
        ..lineTo(12, 41)
        ..lineTo(12, 17)
        ..close(),
      fill,
    );

    canvas.drawPath(
      Path()
        ..moveTo(32, 17.5)
        ..lineTo(42.5, 23.8)
        ..lineTo(42.5, 36.2)
        ..lineTo(32, 42.5)
        ..lineTo(21.5, 36.2)
        ..lineTo(21.5, 23.8)
        ..close(),
      stroke()..color = line.withValues(alpha: line.a * 0.5),
    );

    // Contorno ABERTO: a lacuna no canto superior direito é a quebra.
    canvas.drawPath(
      Path()
        ..moveTo(44.6, 12.6)
        ..lineTo(52, 17)
        ..lineTo(52, 41)
        ..lineTo(32, 53)
        ..lineTo(12, 41)
        ..lineTo(12, 17)
        ..lineTo(32, 5)
        ..lineTo(39.4, 9.4),
      stroke(),
    );

    canvas.drawPath(
      Path()
        ..moveTo(40.4, 6.4)
        ..lineTo(45.8, 15.8),
      stroke(),
    );
  }

  /// Raio dentro de um manômetro com a agulha estourada.
  void _overdrive(Canvas canvas, Paint fill, Paint Function([double]) stroke) {
    final gauge = Path()
      ..moveTo(14, 44.6)
      ..arcToPoint(const Offset(50, 44.6),
          radius: const Radius.circular(22), largeArc: true)
      ..lineTo(44.3, 40.6)
      ..arcToPoint(const Offset(19.7, 40.6),
          radius: const Radius.circular(15),
          largeArc: true,
          clockwise: false)
      ..close();
    canvas
      ..drawPath(gauge, fill)
      ..drawPath(gauge, stroke());

    final needle = Path()
      ..moveTo(34, 30.5)
      ..lineTo(56, 42.5)
      ..lineTo(33.5, 35.5)
      ..close();
    canvas
      ..drawPath(needle, fill)
      ..drawPath(needle, stroke());

    final bolt = Path()
      ..moveTo(31, 16)
      ..lineTo(21.5, 30.5)
      ..lineTo(27.5, 30.5)
      ..lineTo(25.5, 42.5)
      ..lineTo(35.5, 27)
      ..lineTo(29.5, 27)
      ..close();
    canvas
      ..drawPath(bolt, fill)
      ..drawPath(bolt, stroke());
  }

  @override
  bool shouldRepaint(_ModuleIconPainter old) =>
      old.module != module || old.owned != owned;
}
