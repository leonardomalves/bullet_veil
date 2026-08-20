import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'atlas.dart';

final _rng = math.Random();

/// Faíscas de explosão.
///
/// Reaproveita o mesmo atlas e o mesmo `drawRawAtlas` das balas: as faíscas
/// custam praticamente uma chamada de GPU no total, então dá para ser
/// generoso com a quantidade sem pagar em framerate.
class SparkField extends Component {
  SparkField({required this.atlas, this.capacity = 900})
      : super(priority: 12);

  final BulletAtlas atlas;
  final int capacity;

  late final Float32List _x = Float32List(capacity);
  late final Float32List _y = Float32List(capacity);
  late final Float32List _vx = Float32List(capacity);
  late final Float32List _vy = Float32List(capacity);
  late final Float32List _life = Float32List(capacity);
  late final Float32List _maxLife = Float32List(capacity);
  late final Float32List _scale = Float32List(capacity);
  late final Int32List _sprite = Int32List(capacity);

  late final Float32List _xform = Float32List(capacity * 4);
  late final Float32List _texRects = Float32List(capacity * 4);
  late final Int32List _colors = Int32List(capacity);

  late final Paint _paint = Paint()
    ..isAntiAlias = false
    ..blendMode = BlendMode.plus;

  int _count = 0;
  int get count => _count;

  void burst({
    required double x,
    required double y,
    required int color,
    int count = 16,
    double speed = 280,
    double scale = 1,
    double life = 0.5,
  }) {
    for (var i = 0; i < count; i++) {
      if (_count >= capacity) return;
      final j = _count++;
      final a = _rng.nextDouble() * math.pi * 2;
      final v = speed * (0.25 + _rng.nextDouble());
      _x[j] = x;
      _y[j] = y;
      _vx[j] = math.cos(a) * v;
      _vy[j] = math.sin(a) * v;
      _maxLife[j] = life * (0.6 + _rng.nextDouble() * 0.7);
      _life[j] = 0;
      _scale[j] = scale * (0.35 + _rng.nextDouble() * 0.6);
      _sprite[j] = BulletAtlas.id(BulletShape.orb, color);
    }
  }

  void _swapRemove(int i) {
    final last = --_count;
    if (i != last) {
      _x[i] = _x[last];
      _y[i] = _y[last];
      _vx[i] = _vx[last];
      _vy[i] = _vy[last];
      _life[i] = _life[last];
      _maxLife[i] = _maxLife[last];
      _scale[i] = _scale[last];
      _sprite[i] = _sprite[last];
    }
  }

  @override
  void update(double dt) {
    var i = 0;
    while (i < _count) {
      _life[i] += dt;
      if (_life[i] >= _maxLife[i]) {
        _swapRemove(i);
        continue;
      }
      _x[i] += _vx[i] * dt;
      _y[i] += _vy[i] * dt;
      final drag = 1 - 2.4 * dt;
      _vx[i] *= drag;
      _vy[i] *= drag;
      i++;
    }

    for (var k = 0; k < _count; k++) {
      final t = 1 - (_life[k] / _maxLife[k]);
      writeRSTransform(
        _xform,
        k,
        0,
        _scale[k] * (0.4 + 0.6 * t),
        BulletAtlas.cell / 2,
        BulletAtlas.cell / 2,
        _x[k],
        _y[k],
      );
      final r = atlas.rectAt(_sprite[k]);
      final j = k * 4;
      _texRects[j] = r.left;
      _texRects[j + 1] = r.top;
      _texRects[j + 2] = r.right;
      _texRects[j + 3] = r.bottom;
      // `modulate` multiplica o sprite por esta cor, então o alfa aqui faz o
      // fade sem precisar de saveLayer.
      final a = (t.clamp(0.0, 1.0) * 255).toInt();
      _colors[k] = (a << 24) | 0x00FFFFFF;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_count == 0) return;
    canvas.drawRawAtlas(
      atlas.image,
      Float32List.view(_xform.buffer, 0, _count * 4),
      Float32List.view(_texRects.buffer, 0, _count * 4),
      Int32List.view(_colors.buffer, 0, _count),
      BlendMode.modulate,
      null,
      _paint,
    );
  }
}

/// Onda de choque da bomba.
class Shockwave extends Component {
  Shockwave(this.center) : super(priority: 14);

  final Vector2 center;
  double _t = 0;
  static const _duration = 0.55;
  static const _maxRadius = 900.0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / _duration).clamp(0.0, 1.0);
    final r = _maxRadius * Curves.easeOutCubic.transform(p);
    canvas.drawCircle(
      Offset(center.x, center.y),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26 * (1 - p)
        ..blendMode = BlendMode.plus
        ..color = const Color(0xFF35E1F5).withValues(alpha: 0.55 * (1 - p)),
    );
  }
}

/// Texto flutuante (pontos, avisos).
class FloatingText extends PositionComponent {
  FloatingText(
    this.text, {
    required super.position,
    this.color = Colors.white,
    this.fontSize = 26,
    this.duration = 0.8,
  }) : super(priority: 20);

  final String text;
  final Color color;
  final double fontSize;
  final double duration;
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    position.y -= 46 * dt;
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / duration).clamp(0.0, 1.0);
    final alpha = p < 0.7 ? 1.0 : 1 - (p - 0.7) / 0.3;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: color.withValues(alpha: alpha),
          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  }
}

/// Tema visual de um setor (estágio): a paleta do fundo e o tom das estrelas.
class StageTheme {
  const StageTheme(this.name, this.mid, this.nebula, this.starTint);

  final String name;
  final Color mid; // cor do meio do gradiente vertical
  final Color nebula; // cor das manchas de nebulosa
  final Color starTint; // tom das estrelas próximas
}

/// Ciclo de setores — 1 identidade por estágio, repetindo a cada 4.
const stageThemes = <StageTheme>[
  StageTheme('VÉU VIOLETA', Color(0xFF11082A), Color(0xFF3A1B6E), Color(0xFFE8F4FF)),
  StageTheme('CINTURÃO RUBRO', Color(0xFF1F0A14), Color(0xFF6E1B2E), Color(0xFFFFE0D0)),
  StageTheme('MAR ESMERALDA', Color(0xFF07200F), Color(0xFF1B6E3A), Color(0xFFD8FFE8)),
  StageTheme('ABISMO AZUL', Color(0xFF0A1430), Color(0xFF1B3A6E), Color(0xFFD0E8FF)),
];

/// Fundo em estrelas com identidade por estágio: gradiente + nebulosas na cor
/// do setor, com transição suave quando o chefe cai. Progressão que se VÊ.
class Starfield extends Component {
  Starfield({this.layers = 3, this.perLayer = 34}) : super(priority: -100);

  final int layers;
  final int perLayer;
  final List<Float32List> _pos = [];
  final List<double> _speed = [];

  static const double _w = 720;
  static const double _h = 1280;

  int _themeIndex = 0;
  int _prevIndex = 0;
  double _blend = 1; // 0→1 durante a transição

  // Nebulosas: manchas enormes desfocadas que rolam devagar.
  final List<Offset> _nebula = [];
  double _nebulaScroll = 0;

  /// Troca o tema (chamado ao completar um estágio). Transição de ~2.5s.
  void setStage(int stage) {
    final next = (stage - 1) % stageThemes.length;
    if (next == _themeIndex) return;
    _prevIndex = _themeIndex;
    _themeIndex = next;
    _blend = 0;
  }

  StageTheme get theme => stageThemes[_themeIndex];

  @override
  Future<void> onLoad() async {
    final rng = math.Random(9);
    for (var l = 0; l < layers; l++) {
      final buf = Float32List(perLayer * 2);
      for (var i = 0; i < perLayer; i++) {
        buf[i * 2] = rng.nextDouble() * _w;
        buf[i * 2 + 1] = rng.nextDouble() * _h;
      }
      _pos.add(buf);
      _speed.add(28 + l * 46);
    }
    for (var i = 0; i < 3; i++) {
      _nebula.add(Offset(rng.nextDouble() * _w, rng.nextDouble() * _h));
    }
  }

  @override
  void update(double dt) {
    if (_blend < 1) _blend = math.min(1, _blend + dt / 2.5);
    _nebulaScroll += 9 * dt;
    if (_nebulaScroll > _h) _nebulaScroll -= _h;
    for (var l = 0; l < _pos.length; l++) {
      final buf = _pos[l];
      final v = _speed[l] * dt;
      for (var i = 0; i < perLayer; i++) {
        var y = buf[i * 2 + 1] + v;
        if (y > _h) y -= _h;
        buf[i * 2 + 1] = y;
      }
    }
  }

  Color _lerp(Color Function(StageTheme) pick) => Color.lerp(
      pick(stageThemes[_prevIndex]), pick(stageThemes[_themeIndex]), _blend)!;

  @override
  void render(Canvas canvas) {
    final mid = _lerp((t) => t.mid);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF05030F), mid, const Color(0xFF04030C)],
        ).createShader(const Rect.fromLTWH(0, 0, _w, _h)),
    );

    // Nebulosas: baratas (3 círculos borrados), mas mudam a cara do setor.
    final nebColor = _lerp((t) => t.nebula);
    final nebPaint = Paint()
      ..color = nebColor.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);
    for (var i = 0; i < _nebula.length; i++) {
      var y = _nebula[i].dy + _nebulaScroll * (i.isEven ? 1 : 0.6);
      y %= _h + 400;
      canvas.drawCircle(Offset(_nebula[i].dx, y - 200), 190 + i * 60, nebPaint);
    }

    final starTint = _lerp((t) => t.starTint);
    final paint = Paint();
    for (var l = 0; l < _pos.length; l++) {
      final tint = l == _pos.length - 1 ? starTint : Colors.white;
      paint.color = tint.withValues(alpha: 0.14 + l * 0.16);
      final r = 0.9 + l * 0.7;
      final buf = _pos[l];
      for (var i = 0; i < perLayer; i++) {
        canvas.drawCircle(Offset(buf[i * 2], buf[i * 2 + 1]), r, paint);
      }
    }
  }
}

/// Flash de tela: 1 frame branco que desvanece — o ponto final da morte de um
/// chefe.
class ScreenFlash extends Component {
  ScreenFlash({this.duration = 0.32, this.color = Colors.white})
      : super(priority: 90);

  final double duration;
  final Color color;
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = 1 - (_t / duration).clamp(0.0, 1.0);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 720, 1280),
      Paint()..color = color.withValues(alpha: 0.85 * p * p),
    );
  }
}

/// A faixa de anúncio PADRÃO do jogo: fina, translúcida, sempre na mesma
/// altura (logo abaixo do HUD). TODO evento se apresenta com esta cara —
/// chefe, elite, o que vier — mudando só a cor e o texto. Um idioma visual.
class AnnounceBanner extends Component {
  AnnounceBanner(
    this.title, {
    this.accent = const Color(0xFFFF3B5C),
    this.stripes = false,
    this.blinkIcon = false,
    this.duration = 2.1,
  }) : super(priority: 80);

  /// Altura padrão da faixa no arena-space — compartilhada com a versão
  /// Flutter (intro de fase) para os banners serem UM só padrão.
  static const double centerY = 1280 * 0.155;
  static const double halfHeight = 34.0;

  final String title;
  final Color accent;

  /// Listras de perigo rolando (reservado a ameaças: chefe).
  final bool stripes;

  /// Ícone ⚠ piscando antes do texto.
  final bool blinkIcon;

  final double duration;
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / duration).clamp(0.0, 1.0);
    final alpha = p < 0.12
        ? p / 0.12
        : p > 0.8
            ? (1 - p) / 0.2
            : 1.0;
    const cy = centerY;
    const half = halfHeight;

    canvas.drawRect(
      Rect.fromLTRB(0, cy - half, 720, cy + half),
      Paint()..color = const Color(0xFF120514).withValues(alpha: 0.42 * alpha),
    );

    if (stripes) {
      final stripe = Paint()..color = accent.withValues(alpha: 0.55 * alpha);
      for (final (edgeY, dir) in [(cy - half, 1.0), (cy + half - 5, -1.0)]) {
        final off = (_t * 140 * dir) % 44;
        for (var x = -44.0 + off; x < 764; x += 44) {
          canvas.save();
          canvas.translate(x, edgeY);
          canvas.skew(-0.6, 0);
          canvas.drawRect(const Rect.fromLTWH(0, 0, 18, 5), stripe);
          canvas.restore();
        }
      }
    } else {
      // Sem listras: um fio da cor do assunto nas bordas.
      final line = Paint()..color = accent.withValues(alpha: 0.5 * alpha);
      canvas.drawRect(Rect.fromLTWH(0, cy - half, 720, 2), line);
      canvas.drawRect(Rect.fromLTWH(0, cy + half - 2, 720, 2), line);
    }

    final blink = !blinkIcon || math.sin(_t * 12) > -0.5;
    final painter = TextPainter(
      text: TextSpan(
        children: [
          if (blinkIcon && blink)
            TextSpan(
              text: '⚠ ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: accent.withValues(alpha: alpha),
              ),
            ),
          TextSpan(
            text: title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
              color: Colors.white.withValues(alpha: 0.92 * alpha),
              shadows: [Shadow(color: accent.withValues(alpha: 0.6 * alpha), blurRadius: 10)],
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, Offset((720 - painter.width) / 2, cy - painter.height / 2));
  }
}
