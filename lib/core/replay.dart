import 'dart:convert';
import 'dart:io' show gzip;

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gravador de replay do desafio diário (formato v1 — ver
/// docs/arquitetura-leaderboard.md §6).
///
/// Grava a trajetória da nave numa RÉGUA FIXA de 20 Hz de tempo de JOGO
/// (hitstop/slow-mo entram na régua como o jogo os viveu) + eventos. Com a
/// seed determinística do dia, isso é evidência suficiente para heurísticas
/// hoje (F2) e re-simulação amanhã (F3) — por isso já se grava desde a F1,
/// mesmo sem servidor no ar.
class ReplayRecorder {
  ReplayRecorder({
    required this.seed,
    required this.mode,
    required this.clientVersion,
    this.game = 'bullet_veil',
  });

  static const int sampleHz = 20;
  static const double _step = 1 / sampleHz;

  final int seed;
  final String mode;
  final String clientVersion;
  final String game;

  final List<int> _xs = [];
  final List<int> _ys = [];
  final List<Map<String, Object>> _events = [];

  double _acc = 0;
  double _elapsed = 0;
  bool _finished = false;
  int _score = 0;
  int _wave = 0;

  int get sampleCount => _xs.length;
  bool get finished => _finished;

  /// Alimentado a cada frame com o dt de JOGO (efetivo) e a posição da nave.
  /// Reamostra para a régua fixa — frames irregulares não mudam o resultado.
  void sample(double dt, double x, double y) {
    if (_finished || dt <= 0) return;
    _elapsed += dt;
    _acc += dt;
    while (_acc >= _step) {
      _acc -= _step;
      _xs.add(x.round());
      _ys.add(y.round());
    }
  }

  /// Evento discreto (bomba etc.), ancorado no índice da amostra atual —
  /// tempo do evento = t / [sampleHz].
  void event(String type) {
    if (_finished) return;
    _events.add({'t': _xs.length, 'e': type});
  }

  void finish({required int score, required int wave}) {
    if (_finished) return;
    _finished = true;
    _score = score;
    _wave = wave;
  }

  Map<String, Object> get payload => {
        'v': 1,
        'game': game,
        'mode': mode,
        'seed': seed,
        'hz': sampleHz,
        'cv': clientVersion,
        'score': _score,
        'wave': _wave,
        'dur': double.parse(_elapsed.toStringAsFixed(2)),
        'x': _xs,
        'y': _ys,
        'ev': _events,
      };

  String get _json => jsonEncode(payload);

  /// Blob pronto para o POST /v1/runs/{id}: gzip(json) em base64.
  String encode() => base64Encode(gzip.encode(utf8.encode(_json)));

  /// Integridade do payload — o servidor recomputa e compara.
  String get sha256Hex => sha256.convert(utf8.encode(_json)).toString();

  /// Desfaz [encode] (usado por testes e pelo verificador da F3).
  static Map<String, dynamic> decode(String blob) =>
      jsonDecode(utf8.decode(gzip.decode(base64Decode(blob))))
          as Map<String, dynamic>;
}

/// Guarda o último replay do diário localmente. Quando a F1 estiver no ar,
/// o upload lê daqui — e enquanto não está, já acumulamos formato real.
class ReplayVault {
  static const _key = 'replay_last_daily';
  static const _keyMeta = 'replay_last_daily_sha';

  static Future<void> saveDaily(ReplayRecorder r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, r.encode());
    await prefs.setString(_keyMeta, r.sha256Hex);
  }

  static Future<(String blob, String sha)?> lastDaily() async {
    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getString(_key);
    final sha = prefs.getString(_keyMeta);
    if (blob == null || sha == null) return null;
    return (blob, sha);
  }
}
