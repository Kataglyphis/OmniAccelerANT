import 'package:omni_accelerant/utils/json_utils.dart';

/// One visit of `/healthz`'s `detection.recent`; [boxes] is still as ObservANT wrote it.
typedef HealthVisit = ({
  DateTime arrived,
  Duration? stayed,
  String? className,
  Object? boxes,
});

/// ObservANT's `/healthz` answer, read by key in this one file; the page's parts take their fields from here.
class ObservantHealth {
  ObservantHealth._(this._json, this.ok, this._detection);

  /// `null` for anything but an ObservANT `/healthz` body, a JSON object whose `ok` is a bool.
  static ObservantHealth? parse(String? body) {
    final json = decodeJsonObject(body);
    final ok = json?['ok'];
    if (json == null || ok is! bool) {
      return null;
    }
    // `cat` before ObservANT (2026-10-14), so an older camera among the peers still reads.
    final detection = json['detection'] ?? json['cat'];
    return ObservantHealth._(
      json,
      ok,
      detection is Map<String, dynamic> ? detection : null,
    );
  }

  final Map<String, dynamic> _json;

  /// Whether the camera delivers.
  final bool ok;
  final Map<String, dynamic>? _detection;

  /// Why the camera is not ok, in ObservANT's words; `null` while it delivers.
  String? get problem => ok ? null : _text(_json['problem']);

  String get name => _text(_json['name']);
  String get camera => _text(_json['camera']);
  String get version => _text(_json['version']);
  bool get dark => _json['dark'] == true;
  bool get pixelated => _json['privacy'] == 'pixelate';
  bool get inference => _json['inference'] == true;

  /// Whether a language model answers `/ask`.
  bool get answersQuestions => _json['ask'] == true;
  int? get viewers => _whole(_json['viewers']);
  int get modelRuns => _whole(_json['model_runs']) ?? 0;
  List<String> get peers => _texts(_json['peers']);

  /// The classes it watches for; `null` when the body lists none.
  List<String>? get classes =>
      _json['classes'] is List ? _texts(_json['classes']) : null;

  /// The picture's rotation, when it is one of the four the camera takes.
  int? get rotate => switch (_json['rotate']) {
    final int r when r % 90 == 0 && r >= 0 && r < 360 => r,
    _ => null,
  };

  int? get frameWidth => _whole(_frame?['width']);
  int? get frameHeight => _whole(_frame?['height']);
  int? get frameFps => _whole(_frame?['fps']);

  /// Whether the body carries the sampler's `stats`.
  bool get hasStats => _stats != null;

  /// One number of `stats`, by ObservANT's key.
  double? stat(String key) => switch (_stats?[key]) {
    final num value => value.toDouble(),
    _ => null,
  };

  /// One whole number of `stats`.
  int? wholeStat(String key) => _whole(_stats?[key]);

  /// Whether the body carries `detection`.
  bool get hasDetection => _detection != null;
  bool get inView => _detection?['in_view'] == true;
  int get visits => _whole(_detection?['visits']) ?? 0;
  DateTime? get lastSeen => _time(_detection?['last_seen']);

  /// The arrival `/arrival.mp4` shows.
  DateTime? get clip => _time(_detection?['clip']);
  double? get lastScore => switch (_detection?['last_score']) {
    final num value => value.toDouble(),
    _ => null,
  };

  /// The boxes drawn into the picture now, as ObservANT wrote them.
  Object? get boxes => _detection?['boxes'];

  /// Every arrival whose clip is still kept, newest first.
  List<DateTime> get clips => <DateTime>[
    if (_detection?['clips'] case final List times)
      for (final t in times) ?_time(t),
  ];

  /// The latest visits, newest first.
  List<HealthVisit> get recent => <HealthVisit>[
    if (_detection?['recent'] case final List visits)
      for (final visit in visits)
        if (visit is Map<String, dynamic>)
          if (_time(visit['arrived']) case final DateTime arrived)
            (
              arrived: arrived,
              stayed: switch (visit['stayed_s']) {
                final int s => Duration(seconds: s),
                _ => null,
              },
              className: switch (visit['class']) {
                final String c => c,
                _ => null,
              },
              boxes: visit['boxes'],
            ),
  ];

  Map<String, dynamic>? get _frame => switch (_json['frame']) {
    final Map<String, dynamic> frame => frame,
    _ => null,
  };

  Map<String, dynamic>? get _stats => switch (_json['stats']) {
    final Map<String, dynamic> stats => stats,
    _ => null,
  };
}

String _text(Object? value) => value is String ? value : '';

int? _whole(Object? value) => value is int ? value : null;

List<String> _texts(Object? value) => <String>[
  if (value is List)
    for (final item in value)
      if (item is String) item,
];

/// A time ObservANT writes as whole seconds since 1970.
DateTime? _time(Object? seconds) =>
    seconds is int ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000) : null;
