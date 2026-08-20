import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Camada de som do jogo.
///
/// SFX são WAVs sintetizados offline por `tool/gen_audio.py`. A música são
/// TRÊS loops: base + camada de intensidade (volume segue a FÚRIA) tocando
/// sincronizados, e um tema de chefe que entra por crossfade. Qualquer falha
/// de inicialização degrada para silêncio — áudio nunca derruba o jogo.
class Sfx {
  Sfx._();

  static final Sfx instance = Sfx._();

  static const _prefsKey = 'bv.sound';

  static const sfxKeys = <String>[
    'shot_1', 'shot_2', 'shot_3',
    'graze_1', 'graze_2',
    'medal_1', 'medal_2', 'medal_3', 'medal_4',
    'medal_5', 'medal_6', 'medal_7', 'medal_8',
    'expl_small_1', 'expl_small_2', 'expl_small_3',
    'expl_med', 'expl_boss',
    'power', 'cap', 'weapon', 'weaponup', 'oneup',
    'bomb', 'shield', 'death',
    'alarm', 'phase', 'lock',
    'tick', 'stageclear',
    'ui_tap', 'gameover',
    'count_1', 'count_2', 'count_3', 'count_go',
  ];

  static const musicKeys = <String>['music_base', 'music_layer', 'music_boss'];

  static List<String> get allKeys => [...sfxKeys, ...musicKeys];

  static const _baseVol = 0.42;
  static const _layerVol = 0.62;
  static const _bossVol = 0.55;

  final _sources = <String, AudioSource>{};
  final _rng = math.Random();
  final _clock = Stopwatch()..start();

  bool _ready = false;
  bool _enabled = true;

  // throttles (ms) — tiro e graze disparam dezenas de vezes por segundo
  int _lastShot = -1000;
  int _lastGraze = -1000;

  // música
  SoundHandle? _hBase, _hLayer, _hBoss;
  bool _musicOn = false;
  bool _bossMode = false;
  double _intensity = -1;
  Timer? _duckTimer, _bossStopTimer;

  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    if (_ready) SoLoud.instance.setGlobalVolume(value ? 1 : 0);
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_prefsKey, value))
        .ignore();
  }

  Future<void> init() async {
    if (_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;

      await SoLoud.instance.init();
      // Tiros + explosões + medalhas empilham vozes; música é protegida
      // para nunca ser roubada pelo spam de SFX.
      SoLoud.instance.setMaxActiveVoiceCount(32);
      for (final key in allKeys) {
        _sources[key] = await SoLoud.instance.loadAsset('assets/audio/$key.wav');
      }
      SoLoud.instance.setGlobalVolume(_enabled ? 1 : 0);
      _ready = true;
    } catch (e) {
      debugPrint('[Sfx] áudio indisponível, seguindo em silêncio: $e');
      _ready = false;
    }
  }

  // ── One-shots ────────────────────────────────────────────────────────────

  void play(String key, {double volume = 1.0, double pan = 0.0}) {
    if (!_ready || !_enabled) return;
    final source = _sources[key];
    if (source == null) return;
    try {
      SoLoud.instance.play(source, volume: volume, pan: pan.clamp(-1.0, 1.0));
    } catch (_) {
      // voz descartada (limite simultâneo) — irrelevante
    }
  }

  void playVariant(String prefix, int count,
      {double volume = 1.0, double pan = 0.0}) {
    play('${prefix}_${_rng.nextInt(count) + 1}', volume: volume, pan: pan);
  }

  /// Tiro do jogador: sempre presente mas nunca dominante, com variação de
  /// amostra e throttle — é tapete sonoro, não solo.
  void shot() {
    final now = _clock.elapsedMilliseconds;
    if (now - _lastShot < 80) return;
    _lastShot = now;
    playVariant('shot', 3, volume: 0.20);
  }

  /// Tick de graze — frequente, tem que ser agradável.
  void graze() {
    final now = _clock.elapsedMilliseconds;
    if (now - _lastGraze < 45) return;
    _lastGraze = now;
    playVariant('graze', 2, volume: 0.30);
  }

  /// Degrau da escada de medalhas (0..7): o pitch subindo É a corrente.
  void medal(int step, {double pan = 0.0}) {
    play('medal_${(step + 1).clamp(1, 8)}', volume: 0.5, pan: pan);
  }

  void explosionSmall({double pan = 0.0}) =>
      playVariant('expl_small', 3, volume: 0.5, pan: pan);

  void explosionMed({double pan = 0.0}) =>
      play('expl_med', volume: 0.62, pan: pan);

  void explosionBoss() => play('expl_boss', volume: 0.95);

  // ── Música ───────────────────────────────────────────────────────────────

  /// Sobe base + camada pausadas e libera juntas (sub-ms de defasagem) para
  /// os hats da camada baterem em cima do bumbo da base.
  Future<void> startMusic() async {
    if (!_ready) return;
    await stopMusic();
    try {
      final sl = SoLoud.instance;
      _hBase = sl.play(_sources['music_base']!,
          volume: 0, looping: true, paused: true);
      _hLayer = sl.play(_sources['music_layer']!,
          volume: 0, looping: true, paused: true);
      sl.setProtectVoice(_hBase!, true);
      sl.setProtectVoice(_hLayer!, true);
      sl.setPause(_hBase!, false);
      sl.setPause(_hLayer!, false);
      sl.fadeVolume(_hBase!, _baseVol, const Duration(milliseconds: 700));
      _musicOn = true;
      _bossMode = false;
      _intensity = 0;
    } catch (e) {
      debugPrint('[Sfx] música falhou: $e');
    }
  }

  /// Volume da camada de fúria (0..1). Quantizado para não spammar fades.
  void setIntensity(double rank) {
    if (!_musicOn || _bossMode || _hLayer == null) return;
    final q = (rank * 20).roundToDouble() / 20;
    if (q == _intensity) return;
    _intensity = q;
    SoLoud.instance
        .fadeVolume(_hLayer!, q * _layerVol, const Duration(milliseconds: 350));
  }

  /// Crossfade para o tema de chefe (e volta). O loop do chefe SEMPRE começa
  /// do início — entrada no tempo forte, como manda o figurino.
  Future<void> bossMode(bool on) async {
    if (!_ready || !_musicOn || _bossMode == on) return;
    _bossMode = on;
    final sl = SoLoud.instance;
    const xfade = Duration(milliseconds: 900);
    try {
      if (on) {
        _bossStopTimer?.cancel();
        if (_hBoss != null) await sl.stop(_hBoss!);
        _hBoss = sl.play(_sources['music_boss']!, volume: 0, looping: true);
        sl.setProtectVoice(_hBoss!, true);
        sl.fadeVolume(_hBoss!, _bossVol, xfade);
        if (_hBase != null) sl.fadeVolume(_hBase!, 0, xfade);
        if (_hLayer != null) sl.fadeVolume(_hLayer!, 0, xfade);
      } else {
        if (_hBoss != null) {
          final h = _hBoss!;
          sl.fadeVolume(h, 0, xfade);
          _bossStopTimer = Timer(xfade, () => sl.stop(h).ignore());
          _hBoss = null;
        }
        if (_hBase != null) sl.fadeVolume(_hBase!, _baseVol, xfade);
        if (_hLayer != null) {
          sl.fadeVolume(_hLayer!, _intensity.clamp(0, 1) * _layerVol, xfade);
        }
      }
    } catch (_) {}
  }

  /// Abaixa a música por um instante (bomba) — o clássico "duck" que faz o
  /// estouro parecer maior do que é.
  void duck() {
    if (!_musicOn) return;
    final sl = SoLoud.instance;
    const dip = Duration(milliseconds: 90);
    try {
      if (_hBase != null) sl.fadeVolume(_hBase!, _baseVol * 0.15, dip);
      if (_hLayer != null) sl.fadeVolume(_hLayer!, 0, dip);
      if (_hBoss != null) sl.fadeVolume(_hBoss!, _bossVol * 0.15, dip);
      _duckTimer?.cancel();
      _duckTimer = Timer(const Duration(milliseconds: 650), () {
        const back = Duration(milliseconds: 500);
        try {
          if (_bossMode) {
            if (_hBoss != null) sl.fadeVolume(_hBoss!, _bossVol, back);
          } else {
            if (_hBase != null) sl.fadeVolume(_hBase!, _baseVol, back);
            if (_hLayer != null) {
              sl.fadeVolume(_hLayer!, _intensity.clamp(0, 1) * _layerVol, back);
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  void pauseMusic() {
    if (!_ready) return;
    for (final h in [_hBase, _hLayer, _hBoss]) {
      if (h != null) SoLoud.instance.setPause(h, true);
    }
  }

  void resumeMusic() {
    if (!_ready) return;
    for (final h in [_hBase, _hLayer, _hBoss]) {
      if (h != null) SoLoud.instance.setPause(h, false);
    }
  }

  /// Game over: a música morre devagar enquanto o sting toca por cima.
  void fadeOutMusic() {
    if (!_ready) return;
    const out = Duration(milliseconds: 1400);
    for (final h in [_hBase, _hLayer, _hBoss]) {
      if (h != null) SoLoud.instance.fadeVolume(h, 0, out);
    }
    _musicOn = false;
  }

  Future<void> stopMusic() async {
    if (!_ready) return;
    _duckTimer?.cancel();
    _bossStopTimer?.cancel();
    for (final h in [_hBase, _hLayer, _hBoss]) {
      if (h != null) {
        try {
          await SoLoud.instance.stop(h);
        } catch (_) {}
      }
    }
    _hBase = _hLayer = _hBoss = null;
    _musicOn = false;
    _bossMode = false;
  }
}

final sfx = Sfx.instance;
