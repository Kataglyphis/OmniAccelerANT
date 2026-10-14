import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/coco_classes.dart';
import 'package:omni_accelerant/Pages/StreamPage/detection_status.dart'
    show formatLastSeen;
import 'package:omni_accelerant/utils/json_utils.dart';

/// Spots of the picture as fractions of its width and height, from a JSON list of `[x1, y1, x2, y2]`.
List<Rect> parseZones(Object? json) => <Rect>[
  if (json is List)
    for (final zone in json)
      if (zone is List &&
          zone.length == 4 &&
          zone.every((v) => v is num) &&
          (zone[0] as num) < (zone[2] as num) &&
          (zone[1] as num) < (zone[3] as num))
        Rect.fromLTRB(
          (zone[0] as num).toDouble(),
          (zone[1] as num).toDouble(),
          (zone[2] as num).toDouble(),
          (zone[3] as num).toDouble(),
        ),
];

/// [zone] as ObservANT takes it, `[x1, y1, x2, y2]` to three places.
List<double> zoneJson(Rect zone) => [
  for (final v in [zone.left, zone.top, zone.right, zone.bottom])
    (v * 1000).round() / 1000,
];

/// What ObservANT's settings page can change, as `GET /settings` answers it.
class ObservantSettings {
  const ObservantSettings({
    required this.name,
    required this.rotate,
    required this.score,
    this.ignore = const <Rect>[],
    this.classes,
    this.classesLocked = false,
  });

  /// Spots marked "not a cat"; an ObservANT camera before them sends none.
  final List<Rect> ignore;

  /// The COCO classes it watches; `null` for an ObservANT camera that watches only cats and cannot change it.
  final List<String>? classes;

  /// The privacy filter is on, so only observant.toml sets [classes]: a page could otherwise unblur people.
  final bool classesLocked;

  final String name;

  /// Clockwise degrees ObservANT turns its picture by.
  final int rotate;

  /// The certainty a detection needs to count as a cat, 0 to 1.
  final double score;

  /// `null` for anything but an ObservANT camera's answer.
  static ObservantSettings? parse(String? body) {
    final json = decodeJsonObject(body);
    if (json == null) {
      return null;
    }
    final name = json['name'];
    final rotate = json['rotate'];
    final score = json['score'];
    if (name is! String || rotate is! int || score is! num) {
      return null;
    }
    return ObservantSettings(
      name: name,
      rotate: rotate,
      score: score.toDouble(),
      ignore: parseZones(json['ignore']),
      classes: json['classes'] is List
          ? <String>[
              for (final c in json['classes'] as List)
                if (c is String) c,
            ]
          : null,
      classesLocked: json['privacy'] == 'pixelate',
    );
  }
}

/// A recent visit's arrival and the boxes it arrived with, which "not a cat" can ignore after the fact.
class RecentDetection {
  const RecentDetection(this.arrived, this.boxes);

  final DateTime arrived;
  final List<Rect> boxes;
}

/// ObservANT keeps the pictures of this many arrivals, so the page offers no more.
const int _keptPictures = 5;

/// The read-only half of the page, from `/healthz`.
class ObservantInfo {
  const ObservantInfo({
    this.camera = '',
    this.width,
    this.height,
    this.fps,
    this.inference = false,
    this.modelRuns = 0,
    this.visits = 0,
    this.lastScore,
    this.problem,
    this.boxes = const <Rect>[],
    this.version = '',
    this.detections = const <RecentDetection>[],
    this.pixelated = false,
  });

  /// The privacy filter blocks out all but the detected animals; only the settings file sets it.
  final bool pixelated;

  /// The latest arrivals that came with boxes, newest first.
  final List<RecentDetection> detections;

  /// ObservANT's build, as its package stamped it.
  final String version;

  /// The boxes drawn into the picture now, as fractions of it: what "not a cat" would ignore.
  final List<Rect> boxes;

  final String camera;
  final int? width;
  final int? height;
  final int? fps;
  final bool inference;
  final int modelRuns;
  final int visits;

  /// The best score of the last detection, where to set the slider just above for a false one.
  final double? lastScore;

  /// Why the camera is not ok, in ObservANT's words; `null` while it delivers.
  final String? problem;

  static ObservantInfo? parse(String? body) {
    final json = decodeJsonObject(body);
    final ok = json?['ok'];
    if (json == null || ok is! bool) {
      return null;
    }
    final frame = json['frame'];
    // `cat` before ObservANT (2026-10-14).
    final cat = json['detection'] ?? json['cat'];
    int? field(Object? map, String key) =>
        map is Map<String, dynamic> && map[key] is int ? map[key] as int : null;
    return ObservantInfo(
      camera: json['camera'] is String ? json['camera'] as String : '',
      version: json['version'] is String ? json['version'] as String : '',
      pixelated: json['privacy'] == 'pixelate',
      width: field(frame, 'width'),
      height: field(frame, 'height'),
      fps: field(frame, 'fps'),
      inference: json['inference'] == true,
      modelRuns: field(json, 'model_runs') ?? 0,
      visits: field(cat, 'visits') ?? 0,
      problem: ok
          ? null
          : (json['problem'] is String ? json['problem'] as String : ''),
      boxes: parseZones(cat is Map<String, dynamic> ? cat['boxes'] : null),
      detections: <RecentDetection>[
        if (cat is Map<String, dynamic> && cat['recent'] is List)
          for (final visit in cat['recent'] as List)
            if (visit is Map<String, dynamic> &&
                visit['arrived'] is int &&
                parseZones(visit['boxes']).isNotEmpty)
              RecentDetection(
                DateTime.fromMillisecondsSinceEpoch(
                  (visit['arrived'] as int) * 1000,
                ),
                parseZones(visit['boxes']),
              ),
      ].take(_keptPictures).toList(),
      lastScore: cat is Map<String, dynamic> && cat['last_score'] is num
          ? (cat['last_score'] as num).toDouble()
          : null,
    );
  }
}

/// An arrival's picture at [url], 160 px wide, nothing where none is kept.
Widget recentArrivalPicture(String url) => Image.network(
  url,
  width: 160,
  errorBuilder: (_, _, _) => const SizedBox.shrink(),
);

/// The live picture at [url], 320 px wide; tests swap the network out.
Widget cameraPreview(String url) => Image.network(
  url,
  width: 320,
  gaplessPlayback: true,
  errorBuilder: (_, _, _) => const SizedBox.shrink(),
);

/// ObservANT's settings: a live preview, rotation, detection threshold and name, then what it runs.
class CameraSettingsPanel extends StatefulWidget {
  const CameraSettingsPanel({
    super.key,
    required this.fetchSettings,
    required this.saveSettings,
    required this.fetchHealthz,
    this.preview = cameraPreview,
    this.previewInterval = const Duration(seconds: 3),
    this.detectionPicture = recentArrivalPicture,
  });

  /// `GET /settings`, or `null` when no ObservANT answers.
  final Future<String?> Function() fetchSettings;

  /// `POST /settings` with these values; `true` once ObservANT took them.
  final Future<bool> Function(Map<String, Object> update) saveSettings;

  /// `GET /healthz`, or `null`.
  final Future<String?> Function() fetchHealthz;

  final Widget Function(String url) preview;
  final Duration previewInterval;

  /// Builds a recent arrival's picture from its URL; tests swap the network out.
  final Widget Function(String url) detectionPicture;

  @override
  State<CameraSettingsPanel> createState() => _CameraSettingsPanelState();
}

class _CameraSettingsPanelState extends State<CameraSettingsPanel> {
  ObservantSettings? _settings;
  ObservantInfo? _info;
  bool _loaded = false;
  double? _score;
  int _frame = 0;
  Timer? _timer;

  /// False while another tab of the bottom bar shows: go_router keeps this page alive behind it.
  bool _visible = true;
  final TextEditingController _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(widget.previewInterval, (_) {
      if (mounted && _visible && _settings != null) {
        setState(() => _frame++);
        // With the picture, so "not a cat" offers the boxes it shows.
        unawaited(_refreshInfo());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      fetchOrNull(widget.fetchSettings),
      fetchOrNull(widget.fetchHealthz),
    ]);
    if (!mounted) {
      return;
    }
    final settings = ObservantSettings.parse(results[0]);
    setState(() {
      _loaded = true;
      _settings = settings;
      _info = ObservantInfo.parse(results[1]);
      _score = settings?.score;
      _frame++;
      if (settings != null && _name.text.isEmpty) {
        _name.text = settings.name;
      }
    });
  }

  Future<void> _refreshInfo() async {
    final info = ObservantInfo.parse(await fetchOrNull(widget.fetchHealthz));
    if (mounted && info != null) {
      setState(() => _info = info);
    }
  }

  Future<void> _save(Map<String, Object> update) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    bool ok;
    try {
      ok = await widget.saveSettings(update);
    } on Object {
      ok = false;
    }
    messenger?.showSnackBar(
      SnackBar(content: Text(ok ? l10n.cameraSaved : l10n.cameraSaveFailed)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      // Back in view: the camera may have moved on, so read it again rather than show a stale frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _load();
        }
      });
    }
    _visible = visible;
    final l10n = AppLocalizations.of(context)!;
    final settings = _settings;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (settings == null) {
      return Text(l10n.cameraNotReachable, textAlign: TextAlign.center);
    }
    final score = _score ?? settings.score;
    final heading = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 12,
      children: [
        Text(
          l10n.cameraSettingsTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            foregroundPainter: _IgnoredPainter(settings.ignore),
            child: widget.preview('/snapshot.jpg?frame=$_frame'),
          ),
        ),
        if (_info?.boxes case final boxes? when boxes.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              spacing: 4,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.block),
                  label: Text(l10n.cameraFalseAlarm),
                  onPressed: () => _save({
                    'ignore': [
                      ...settings.ignore,
                      ...boxes,
                    ].map(zoneJson).toList(),
                  }),
                ),
                Text(
                  l10n.cameraFalseAlarmHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        if (_info?.detections case final detections?
            when detections.isNotEmpty) ...[
          Text(l10n.cameraRecentDetections, style: heading),
          Text(
            l10n.cameraRecentDetectionsHelp,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final found in detections)
                _DetectionCard(
                  picture: widget.detectionPicture(
                    '/arrival.jpg?t=${found.arrived.millisecondsSinceEpoch ~/ 1000}',
                  ),
                  time: formatLastSeen(
                    found.arrived,
                    DateTime.now(),
                    Localizations.localeOf(context).toString(),
                  ),
                  ignored: _ignores(settings.ignore, found.boxes),
                  onNotACat: () => _save({
                    'ignore': [
                      ...settings.ignore,
                      ...found.boxes.where(
                        (box) => !_ignores(settings.ignore, [box]),
                      ),
                    ].map(zoneJson).toList(),
                  }),
                ),
            ],
          ),
        ],
        if (settings.ignore.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(l10n.cameraIgnoredSpots(settings.ignore.length)),
              TextButton(
                onPressed: () => _save({'ignore': <List<double>>[]}),
                child: Text(l10n.cameraWatchAgain),
              ),
            ],
          ),
        Text(l10n.cameraRotation, style: heading),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            IconButton(
              icon: const Icon(Icons.rotate_left),
              tooltip: l10n.cameraRotateLeft,
              onPressed: () => _save({'rotate': (settings.rotate + 270) % 360}),
            ),
            // Fixed, so the buttons stay put between 0° and 270°.
            SizedBox(
              width: 48,
              child: Text('${settings.rotate}°', textAlign: TextAlign.center),
            ),
            IconButton(
              icon: const Icon(Icons.rotate_right),
              tooltip: l10n.cameraRotateRight,
              onPressed: () => _save({'rotate': (settings.rotate + 90) % 360}),
            ),
          ],
        ),
        Text(l10n.cameraSensitivity, style: heading),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Slider(
                value: score.clamp(0.05, 0.95),
                min: 0.05,
                max: 0.95,
                divisions: 18,
                label: '${(score * 100).round()} %',
                onChanged: (value) => setState(() => _score = value),
                onChangeEnd: (value) =>
                    _save({'score': (value * 100).round() / 100}),
              ),
              Text(l10n.cameraScoreValue((score * 100).round())),
              if (_info?.lastScore case final last?)
                Text(l10n.cameraLastScore((last * 100).round())),
              Text(
                l10n.cameraSensitivityHelp,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Text(l10n.cameraName, style: heading),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Row(
            spacing: 8,
            children: [
              Expanded(child: TextField(controller: _name, maxLength: 64)),
              FilledButton(
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isNotEmpty) {
                    _save({'name': name});
                  }
                },
                child: Text(l10n.cameraSave),
              ),
            ],
          ),
        ),
        if (settings.classes case final classes?) ...[
          Text(l10n.cameraClasses, style: heading),
          _ClassesEditor(
            classes: classes,
            locked: settings.classesLocked,
            onChanged: (next) => _save({'classes': next}),
          ),
        ],
        if (_info case final info?) _InfoTable(info: info),
      ],
    );
  }
}

/// The watched classes as chips, each removable while another stays, and a menu to add one; [locked], only shown.
class _ClassesEditor extends StatelessWidget {
  const _ClassesEditor({
    required this.classes,
    required this.onChanged,
    this.locked = false,
  });

  final List<String> classes;
  final void Function(List<String> classes) onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final addable = cocoClasses.where((c) => !classes.contains(c)).toList();
    final language = Localizations.localeOf(context).languageCode;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        spacing: 8,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final c in classes)
                InputChip(
                  label: Text(classLabel(c, language)),
                  onDeleted: !locked && classes.length > 1
                      ? () => onChanged([
                          for (final other in classes)
                            if (other != c) other,
                        ])
                      : null,
                ),
            ],
          ),
          if (!locked)
            DropdownMenu<String>(
              key: const ValueKey('add-class'),
              hintText: l10n.cameraAddClass,
              enableFilter: true,
              requestFocusOnTap: true,
              dropdownMenuEntries: [
                for (final c in addable)
                  DropdownMenuEntry<String>(
                    value: c,
                    label: classLabel(c, language),
                  ),
              ],
              onSelected: (c) {
                if (c != null && !classes.contains(c)) {
                  onChanged([...classes, c]);
                }
              },
            ),
          Text(
            locked ? l10n.cameraClassesLocked : l10n.cameraClassesHelp,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Every one of [boxes] is already among the [ignored] spots, as ObservANT rounds them.
bool _ignores(List<Rect> ignored, List<Rect> boxes) => boxes.every(
  (box) => ignored.any((spot) => listEquals(zoneJson(spot), zoneJson(box))),
);

/// One recent arrival on the Camera page: its picture, its time, and "not a cat" or that it is ignored.
class _DetectionCard extends StatelessWidget {
  const _DetectionCard({
    required this.picture,
    required this.time,
    required this.ignored,
    required this.onNotACat,
  });

  final Widget picture;
  final String time;
  final bool ignored;
  final VoidCallback onNotACat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: 168,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: picture),
          Text(time, style: Theme.of(context).textTheme.bodySmall),
          if (ignored)
            Text(
              l10n.cameraSpotIgnored,
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.block, size: 16),
              label: Text(l10n.cameraWasFalseAlarm),
              onPressed: onNotACat,
            ),
        ],
      ),
    );
  }
}

/// The spots marked "not a cat", grey over the preview, so the owner sees what no longer counts.
class _IgnoredPainter extends CustomPainter {
  const _IgnoredPainter(this.zones);

  final List<Rect> zones;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x66808080);
    final edge = Paint()
      ..color = const Color(0xCCBDBDBD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final zone in zones) {
      final rect = Rect.fromLTRB(
        zone.left * size.width,
        zone.top * size.height,
        zone.right * size.width,
        zone.bottom * size.height,
      );
      canvas
        ..drawRect(rect, fill)
        ..drawRect(rect, edge);
    }
  }

  @override
  bool shouldRepaint(_IgnoredPainter old) => old.zones != zones;
}

class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.info});

  final ObservantInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rows = <(String, String)>[
      if (info.problem case final problem?) (l10n.cameraProblem, problem),
      (l10n.cameraDevice, info.camera),
      if (info.width != null && info.height != null)
        (l10n.cameraResolution, '${info.width} × ${info.height}'),
      if (info.fps case final fps? when fps > 0)
        (l10n.cameraFrameRate, '$fps fps'),
      (l10n.cameraDetection, info.inference ? l10n.cameraOn : l10n.cameraOff),
      (
        l10n.cameraPrivacy,
        info.pixelated ? l10n.cameraPrivacyPixelate : l10n.cameraPrivacyOff,
      ),
      (l10n.cameraModelRuns, '${info.modelRuns}'),
      (l10n.cameraVisits, '${info.visits}'),
      if (info.version.isNotEmpty) (l10n.cameraVersion, info.version),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(l10n.cameraInfo, style: Theme.of(context).textTheme.titleMedium),
          for (final (label, value) in rows)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
