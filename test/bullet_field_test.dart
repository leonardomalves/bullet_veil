import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/game/arena.dart';
import 'package:bullet_veil/game/atlas.dart';
import 'package:bullet_veil/game/bullet_field.dart';

void main() {
  test('atlas cobre todas as combinações forma × cor', () async {
    final atlas = await BulletAtlas.generate();
    for (final shape in BulletShape.values) {
      for (var c = 0; c < BulletAtlas.cols; c++) {
        final r = atlas.rectAt(BulletAtlas.id(shape, c));
        expect(r.width, BulletAtlas.cell);
        expect(r.height, BulletAtlas.cell);
        expect(r.left, c * BulletAtlas.cell);
        expect(r.top, shape.index * BulletAtlas.cell);
      }
    }
    expect(atlas.image.width, (BulletAtlas.cols * BulletAtlas.cell).toInt());
  });

  test('spawn, integração e cull mantêm a contagem coerente', () async {
    final atlas = await BulletAtlas.generate();
    final field = BulletField(atlas: atlas, capacity: 50);

    for (var i = 0; i < 10; i++) {
      field.spawn(
        x: 100 + i * 10,
        y: 400,
        vx: 0,
        vy: 300,
        shape: BulletShape.orb,
        color: 0,
      );
    }
    expect(field.count, 10);

    // Um segundo de queda não deve descartar nada (400 → 700, dentro da tela).
    field.update(1.0);
    expect(field.count, 10);

    // Tempo suficiente para todas passarem da margem de cull.
    for (var i = 0; i < 60; i++) {
      field.update(1 / 60);
    }
    field.update(5.0);
    expect(field.count, 0, reason: 'balas fora da tela deveriam ser removidas');
  });

  test('respeita o teto de capacidade sem estourar', () async {
    final atlas = await BulletAtlas.generate();
    final field = BulletField(atlas: atlas, capacity: 8);
    for (var i = 0; i < 100; i++) {
      field.spawn(
        x: 300,
        y: 300,
        vx: 0,
        vy: 0,
        shape: BulletShape.orb,
        color: 1,
      );
    }
    expect(field.count, 8);
    expect(field.isFull, isTrue);
  });

  test('colisão com a nave: acerto, graze e imunidade', () async {
    final atlas = await BulletAtlas.generate();
    final field = BulletField(atlas: atlas, capacity: 20);

    // Uma em cima da nave, uma na faixa de graze, uma longe.
    field.spawn(x: 360, y: 900, vx: 0, vy: 0, shape: BulletShape.orb, color: 0);
    field.spawn(x: 360, y: 880, vx: 0, vy: 0, shape: BulletShape.orb, color: 0);
    field.spawn(x: 100, y: 200, vx: 0, vy: 0, shape: BulletShape.orb, color: 0);

    var grazes = 0;
    final hit = field.checkPlayer(
      px: 360,
      py: 900,
      hitRadius: kPlayerHitRadius,
      grazeRadius: kGrazeRadius,
      onGraze: () => grazes++,
      vulnerable: true,
    );

    expect(hit, isTrue);
    expect(grazes, 2, reason: 'a de cima e a de 20px devem contar graze');

    // Graze não repete para a mesma bala.
    final before = grazes;
    field.checkPlayer(
      px: 360,
      py: 900,
      hitRadius: kPlayerHitRadius,
      grazeRadius: kGrazeRadius,
      onGraze: () => grazes++,
      vulnerable: true,
    );
    expect(grazes, before);

    // Invulnerável não toma dano, mas ainda grazeia.
    final hitWhileInvuln = field.checkPlayer(
      px: 360,
      py: 900,
      hitRadius: kPlayerHitRadius,
      grazeRadius: kGrazeRadius,
      onGraze: () {},
      vulnerable: false,
    );
    expect(hitWhileInvuln, isFalse);
  });

  test('hitCircle remove só as balas que acertam', () async {
    final atlas = await BulletAtlas.generate();
    final field = BulletField(atlas: atlas, capacity: 20);
    for (var i = 0; i < 6; i++) {
      field.spawn(
        x: 200 + i * 60,
        y: 300,
        vx: 0,
        vy: 0,
        shape: BulletShape.orb,
        color: 2,
      );
    }
    // Alvo de raio 40 em x=200 pega só a primeira.
    expect(field.hitCircle(200, 300, 40), 1);
    expect(field.count, 5);
  });

  test('clear devolve a contagem e zera o campo', () async {
    final atlas = await BulletAtlas.generate();
    final field = BulletField(atlas: atlas, capacity: 20);
    for (var i = 0; i < 7; i++) {
      field.spawn(
        x: 300,
        y: 300,
        vx: 0,
        vy: 0,
        shape: BulletShape.orb,
        color: 3,
      );
    }
    var seen = 0;
    expect(field.clear((x, y, s) => seen++), 7);
    expect(seen, 7);
    expect(field.count, 0);
  });

  /// Renderiza o caminho real (`BulletField.render` → `drawRawAtlas`) num PNG.
  ///
  /// É o teste que importa mais: valida a matemática do RSTransform. Se a
  /// âncora ou o sinal do seno estiverem errados, as balas saem deslocadas ou
  /// giradas em torno do canto — e isso só se vê olhando.
  test('gera prova visual do render em lote', () async {
    final atlas = await BulletAtlas.generate();
    // Mesma configuração das balas inimigas em jogo: blend normal.
    final field =
        BulletField(atlas: atlas, capacity: 4000, additive: false);

    // Uma linha por forma, uma coluna por cor: confere posicionamento exato.
    for (final shape in BulletShape.values) {
      for (var c = 0; c < BulletAtlas.cols; c++) {
        field.spawn(
          x: 60 + c * 76,
          y: 70 + shape.index * 76,
          vx: 0,
          vy: 0,
          shape: shape,
          color: c,
          faceVelocity: false,
        );
      }
    }

    // Leque rotacionado: prova que a rotação acontece em torno do CENTRO.
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi * 2 / 24;
      field.spawn(
        x: 360 + math.cos(a) * 150,
        y: 700 + math.sin(a) * 150,
        vx: math.cos(a),
        vy: math.sin(a),
        shape: BulletShape.dart,
        color: i % BulletAtlas.cols,
      );
    }

    // Densidade realista de padrão de chefe, espalhada pela metade de baixo:
    // é essa a leitura que precisa continuar possível.
    final rng = math.Random(3);
    for (var i = 0; i < 500; i++) {
      field.spawn(
        x: rng.nextDouble() * kArenaWidth,
        y: 880 + rng.nextDouble() * 380,
        vx: 0,
        vy: 0,
        shape: BulletShape.values[rng.nextInt(BulletShape.values.length)],
        color: rng.nextInt(BulletAtlas.cols),
        faceVelocity: false,
      );
    }

    field.update(0); // escreve os buffers de transform
    expect(field.count, 40 + 24 + 500);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, kArenaWidth, kArenaHeight),
      Paint()..color = const Color(0xFF05030F),
    );
    field.render(canvas);

    final image = await recorder
        .endRecording()
        .toImage(kArenaWidth.toInt(), kArenaHeight.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final out = File('build/bullet_render.png');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    expect(await out.length(), greaterThan(0));
  });
}
