import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

/// What the cat cam's settings page can change, as `GET /settings` answers it.
class CatCamSettings {
  const CatCamSettings({
    required this.name,
    required this.rotate,
    required this.score,
  });

  final String name;

  /// Clockwise degrees the cat cam turns its picture by.
  final int rotate;

  /// The certainty a detection needs to count as a cat, 0 to 1.
  final double score;

  /// `null` for anything but a cat cam's answer.
  static CatCamSettings? parse(String? body) {
    if (body == null) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final name = json['name'];
    final rotate = json['rotate'];
    final score = json['score'];
    if (name is! String || rotate is! int || score is! num) {
      return null;
    }
    return CatCamSettings(name: name, rotate: rotate, score: score.toDouble());
  }
}

/// The read-only half of the page, from `/healthz`.
class CatCamInfo {
  const CatCamInfo({
    this.camera = '',
    this.width,
    this.height,
    this.fps,
    this.inference = false,
    this.modelRuns = 0,
    this.visits = 0,
  });

  final String camera;
  final int? width;
  final int? height;
  final int? fps;
  final bool inference;
  final int modelRuns;
  final int visits;

  static CatCamInfo? parse(String? body) {
    if (body == null) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic> || json['ok'] != true) {
      return null;
    }
    final frame = json['frame'];
    final cat = json['cat'];
    int? field(Object? map, String key) =>
        map is Map<String, dynamic> && map[key] is int ? map[key] as int : null;
    return CatCamInfo(
      camera: json['camera'] is String ? json['camera'] as String : '',
      width: field(frame, 'width'),
      height: field(frame, 'height'),
      fps: field(frame, 'fps'),
      inference: json['inference'] == true,
      modelRuns: field(json, 'model_runs') ?? 0,
      visits: field(cat, 'visits') ?? 0,
    );
  }
}

/// The live picture at [url], 320 px wide; tests swap the network out.
Widget cameraPreview(String url) => Image.network(
  url,
  width: 320,
  gaplessPlayback: true,
  errorBuilder: (_, _, _) => const SizedBox.shrink(),
);

/// The cat cam's settings: a live preview, rotation, detection threshold and name, then what it runs.
class CameraSettingsPanel extends StatefulWidget {
  const CameraSettingsPanel({
    super.key,
    required this.fetchSettings,
    required this.saveSettings,
    required this.fetchHealthz,
    this.preview = cameraPreview,
    this.previewInterval = const Duration(seconds: 3),
  });

  /// `GET /settings`, or `null` when no cat cam answers.
  final Future<String?> Function() fetchSettings;

  /// `POST /settings` with these values; `true` once the cat cam took them.
  final Future<bool> Function(Map<String, Object> update) saveSettings;

  /// `GET /healthz`, or `null`.
  final Future<String?> Function() fetchHealthz;

  final Widget Function(String url) preview;
  final Duration previewInterval;

  @override
  State<CameraSettingsPanel> createState() => _CameraSettingsPanelState();
}

class _CameraSettingsPanelState extends State<CameraSettingsPanel> {
  CatCamSettings? _settings;
  CatCamInfo? _info;
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
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  /// A fetch that throws reads as no cat cam, like one that answers nothing.
  static Future<String?> _quietly(Future<String?> Function() fetch) async {
    try {
      return await fetch();
    } on Object {
      return null;
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _quietly(widget.fetchSettings),
      _quietly(widget.fetchHealthz),
    ]);
    if (!mounted) {
      return;
    }
    final settings = CatCamSettings.parse(results[0]);
    setState(() {
      _loaded = true;
      _settings = settings;
      _info = CatCamInfo.parse(results[1]);
      _score = settings?.score;
      _frame++;
      if (settings != null && _name.text.isEmpty) {
        _name.text = settings.name;
      }
    });
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
          child: widget.preview('/snapshot.jpg?frame=$_frame'),
        ),
        Text(l10n.cameraRotation, style: heading),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            IconButton(
              icon: const Icon(Icons.rotate_left),
              tooltip: l10n.catRotateLeft,
              onPressed: () => _save({'rotate': (settings.rotate + 270) % 360}),
            ),
            // Fixed, so the buttons stay put between 0° and 270°.
            SizedBox(
              width: 48,
              child: Text('${settings.rotate}°', textAlign: TextAlign.center),
            ),
            IconButton(
              icon: const Icon(Icons.rotate_right),
              tooltip: l10n.catRotateRight,
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
        if (_info case final info?) _InfoTable(info: info),
      ],
    );
  }
}

class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.info});

  final CatCamInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rows = <(String, String)>[
      (l10n.cameraDevice, info.camera),
      if (info.width != null && info.height != null)
        (l10n.cameraResolution, '${info.width} × ${info.height}'),
      if (info.fps case final fps? when fps > 0)
        (l10n.cameraFrameRate, '$fps fps'),
      (l10n.cameraDetection, info.inference ? l10n.cameraOn : l10n.cameraOff),
      (l10n.cameraModelRuns, '${info.modelRuns}'),
      (l10n.cameraVisits, '${info.visits}'),
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
