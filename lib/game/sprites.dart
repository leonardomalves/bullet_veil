import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Uma folha de sprites: a imagem + como os frames estão arrumados nela.
class SpriteSheet {
  SpriteSheet({
    required this.image,
    required this.frameWidth,
    required this.frameHeight,
    required this.cols,
    required this.count,
  });

  final ui.Image image;
  final double frameWidth;
  final double frameHeight;
  final int cols;
  final int count;

  /// Recorte do frame [i] dentro da folha.
  Rect rectAt(int i) {
    final k = i % count;
    return Rect.fromLTWH(
      (k % cols) * frameWidth,
      (k ~/ cols) * frameHeight,
      frameWidth,
      frameHeight,
    );
  }
}

/// Sprites renderizados offline a partir dos modelos 3D em `art/models/`.
///
/// Carregar é OPCIONAL por design: se a pasta não estiver empacotada (testes
/// headless, build sem os assets), tudo fica nulo e cada `render()` cai no
/// desenho vetorial procedural que sempre existiu. Mesmo contrato do áudio e
/// dos anúncios — arte que falta degrada, não derruba.
class Sprites {
  Sprites._();

  static final Sprites instance = Sprites._();

  static const _names = <String>[
    'boss_dreadnought', 'boss_mantis', 'boss_core',
    'enemy_elite', 'enemy_heavy', 'enemy_freighter', 'enemy_ringer',
    'enemy_spinner', 'enemy_grunt', 'enemy_kamikaze', 'enemy_sniper',
    'enemy_runner',
    'player_aurora', 'player_crimson', 'player_gold', 'player_voidfire',
    'player_spectre',
    'drone_wingman', 'option_satellite',
    'pickup_capsule', 'pickup_medal',
  ];

  final _sheets = <String, SpriteSheet>{};
  bool _ready = false;

  bool get ready => _ready;

  SpriteSheet? operator [](String name) => _sheets[name];

  Future<void> load() async {
    if (_ready) return;
    for (final name in _names) {
      try {
        final meta = jsonDecode(
          await rootBundle.loadString('assets/sprites/$name.json'),
        ) as Map<String, dynamic>;
        final bytes = await rootBundle.load('assets/sprites/$name.png');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        _sheets[name] = SpriteSheet(
          image: frame.image,
          frameWidth: (meta['frameWidth'] as num).toDouble(),
          frameHeight: (meta['frameHeight'] as num).toDouble(),
          cols: meta['cols'] as int,
          count: meta['count'] as int,
        );
      } catch (_) {
        // Sprite ausente: este arquétipo segue no desenho procedural.
      }
    }
    _ready = _sheets.isNotEmpty;
    if (!_ready) {
      debugPrint('[Sprites] nenhuma folha carregada, seguindo em vetor');
    }
  }

  /// Desenha o frame [frame] de [name] centrado na origem, ocupando um
  /// quadrado de lado [size]. [tint] multiplica a cor (é assim que um mesmo
  /// modelo neutro atende às várias cores de paleta do mesmo arquétipo).
  ///
  /// Retorna `false` se a folha não existir — quem chama desenha o vetor.
  bool draw(
    Canvas canvas,
    String name, {
    required double size,
    int frame = 0,
    Color? tint,
    double opacity = 1,
    BlendMode tintMode = BlendMode.modulate,
  }) {
    final sheet = _sheets[name];
    if (sheet == null) return false;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    if (tint != null) {
      paint.colorFilter = ColorFilter.mode(tint, tintMode);
    }
    if (opacity < 1) {
      paint.color = paint.color.withValues(alpha: opacity);
    }
    canvas.drawImageRect(
      sheet.image,
      sheet.rectAt(frame),
      Rect.fromCenter(center: Offset.zero, width: size, height: size),
      paint,
    );
    return true;
  }
}

final sprites = Sprites.instance;
