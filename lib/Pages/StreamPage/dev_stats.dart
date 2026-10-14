import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/utils/json_utils.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_controller.dart';

/// ObservANT's own numbers, from `/healthz`'s `stats`; a field it cannot measure is `null`.
@immutable
class ServerStats {
  const ServerStats({
    this.captureFps,
    this.configuredFps,
    this.modelMs,
    this.modelRunsPerSecond,
    this.cpuPercent,
    this.cores,
    this.rssMb,
    this.load1m,
    this.temperatureC,
    this.uptime,
    this.viewers,
  });

  final double? captureFps;
  final int? configuredFps;
  final double? modelMs;
  final double? modelRunsPerSecond;

  /// Of one core: 100 is one core busy.
  final double? cpuPercent;
  final int? cores;
  final double? rssMb;
  final double? load1m;
  final double? temperatureC;
  final Duration? uptime;
  final int? viewers;

  /// `null` for anything but an ObservANT camera's `/healthz` that carries `stats`.
  static ServerStats? fromHealthz(String? body) {
    final json = decodeJsonObject(body);
    final stats = json?['stats'];
    if (json == null || stats is! Map<String, dynamic>) {
      return null;
    }
    double? number(Object? v) => v is num ? v.toDouble() : null;
    int? whole(Object? v) => v is int ? v : null;
    final frame = json['frame'];
    final uptime = whole(stats['uptime_s']);
    return ServerStats(
      captureFps: number(stats['capture_fps']),
      configuredFps: frame is Map<String, dynamic> ? whole(frame['fps']) : null,
      modelMs: number(stats['model_ms']),
      modelRunsPerSecond: number(stats['model_runs_per_s']),
      cpuPercent: number(stats['cpu_percent']),
      cores: whole(stats['cores']),
      rssMb: number(stats['rss_mb']),
      load1m: number(stats['load_1m']),
      temperatureC: number(stats['temperature_c']),
      uptime: uptime == null ? null : Duration(seconds: uptime),
      viewers: whole(json['viewers']),
    );
  }
}

/// A "Stats" button that opens a panel of geeky numbers: ObservANT's from `/healthz`, refreshed
/// every [interval] while open, and the browser's own from [playback].
class DevStatsPanel extends StatefulWidget {
  const DevStatsPanel({
    super.key,
    required this.fetch,
    required this.playback,
    this.interval = const Duration(seconds: 2),
  });

  /// `/healthz`'s body, or `null` when it does not answer.
  final Future<String?> Function() fetch;

  /// The stream's [PlaybackStats]; `null` where the page plays none.
  final ValueListenable<PlaybackStats?>? Function() playback;

  final Duration interval;

  @override
  State<DevStatsPanel> createState() => _DevStatsPanelState();
}

class _DevStatsPanelState extends State<DevStatsPanel> {
  bool _open = false;
  ServerStats? _server;
  Timer? _timer;

  void _toggle() {
    setState(() => _open = !_open);
    _timer?.cancel();
    _timer = null;
    if (_open) {
      unawaited(_poll());
      _timer = Timer.periodic(widget.interval, (_) => unawaited(_poll()));
    }
  }

  Future<void> _poll() async {
    final stats = ServerStats.fromHealthz(await fetchOrNull(widget.fetch));
    if (mounted && _open) {
      setState(() => _server = stats);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final button = TextButton.icon(
      onPressed: _toggle,
      icon: Icon(_open ? Icons.expand_less : Icons.query_stats),
      label: Text(l10n.devStats),
    );
    if (!_open) {
      return button;
    }
    final playback = widget.playback();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: playback == null
                  ? _table(context, _rows(l10n, _server, null))
                  : ValueListenableBuilder<PlaybackStats?>(
                      valueListenable: playback,
                      builder: (context, browser, _) =>
                          _table(context, _rows(l10n, _server, browser)),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, List<(String, String)> rows) {
    final mono = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace');
    if (rows.isEmpty) {
      return Text(AppLocalizations.of(context)!.devStatsNone, style: mono);
    }
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        for (final (label, value) in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: Text(label, style: mono),
              ),
              Text(value, style: mono),
            ],
          ),
      ],
    );
  }
}

/// The panel's rows, those the numbers at hand fill.
List<(String, String)> _rows(
  AppLocalizations l10n,
  ServerStats? server,
  PlaybackStats? browser,
) {
  String fixed(double v, int places) => v.toStringAsFixed(places);
  return <(String, String)>[
    if (server?.captureFps case final fps?)
      (
        l10n.devStatsCamera,
        l10n.devStatsCameraValue(
          fixed(fps, 1),
          '${server?.configuredFps ?? '?'}',
        ),
      ),
    if (server?.modelMs case final ms?)
      (
        l10n.devStatsModel,
        l10n.devStatsModelValue(
          '${ms.round()}',
          fixed(server?.modelRunsPerSecond ?? 0, 2),
        ),
      ),
    if (server?.cpuPercent case final cpu?)
      (
        l10n.devStatsCpu,
        l10n.devStatsCpuValue(
          fixed(cpu, 1),
          '${server?.cores ?? '?'}',
          fixed(server?.load1m ?? 0, 2),
        ),
      ),
    if (server?.rssMb case final mb?) (l10n.devStatsMemory, '${mb.round()} MB'),
    if (server?.temperatureC case final c?)
      (l10n.devStatsTemperature, '${fixed(c, 1)} °C'),
    if (server?.uptime case final up?)
      (
        l10n.devStatsUptime,
        l10n.devStatsUptimeValue('${up.inHours}', '${up.inMinutes % 60}'),
      ),
    if (server?.viewers case final viewers?) (l10n.devStatsViewers, '$viewers'),
    if (browser != null)
      (
        l10n.devStatsBrowser,
        l10n.devStatsBrowserValue(
          fixed(browser.fps, 1),
          '${browser.width} × ${browser.height}',
          '${browser.dropped}',
        ),
      ),
  ];
}
