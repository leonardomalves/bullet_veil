import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bullet_veil/core/sfx.dart';

/// Prova que cada chave do Sfx tem um WAV real, mono 44.1kHz, e AUDÍVEL —
/// pega tanto chave sem arquivo quanto síntese que saiu silenciosa.
void main() {
  ({int channels, int rate, double peak}) parseWav(Uint8List b) {
    final d = ByteData.sublistView(b);
    expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
    final channels = d.getUint16(22, Endian.little);
    final rate = d.getUint32(24, Endian.little);
    // Header canônico do módulo `wave` do Python: dados a partir do byte 44.
    expect(String.fromCharCodes(b.sublist(36, 40)), 'data');
    var peak = 0;
    for (var i = 44; i + 1 < b.length; i += 2) {
      final v = d.getInt16(i, Endian.little).abs();
      if (v > peak) peak = v;
    }
    return (channels: channels, rate: rate, peak: peak / 32767);
  }

  test('todos os WAVs existem, são mono 44.1kHz e não-silenciosos', () {
    for (final key in Sfx.allKeys) {
      final f = File('assets/audio/$key.wav');
      expect(f.existsSync(), isTrue, reason: 'falta assets/audio/$key.wav');
      final wav = parseWav(f.readAsBytesSync());
      expect(wav.channels, 1, reason: '$key não é mono');
      expect(wav.rate, 44100, reason: '$key não é 44.1kHz');
      expect(wav.peak, greaterThan(0.05), reason: '$key saiu silencioso');
    }
  });

  test('base e camada da música têm o MESMO tamanho (loops sincronizados)', () {
    final base = File('assets/audio/music_base.wav').lengthSync();
    final layer = File('assets/audio/music_layer.wav').lengthSync();
    expect(base, layer,
        reason: 'loops de tamanhos diferentes derivam e viram mingau rítmico');
  });

  test('a escada de medalhas cobre os 8 degraus do jogo', () {
    for (var i = 1; i <= 8; i++) {
      expect(Sfx.sfxKeys, contains('medal_$i'));
    }
  });
}
