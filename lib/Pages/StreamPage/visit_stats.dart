import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/utils/json_utils.dart';
import 'package:omni_accelerant/Pages/StreamPage/detection_status.dart';

/// One visit from ObservANT's `/visits`: when it arrived, and how long it stayed once it had left.
typedef Stay = ({DateTime arrived, Duration? stayed});

/// The visits in `/visits`'s body, newest first; empty for anything else.
List<Stay> staysFromJson(String? body) {
  final visits = decodeJsonObject(body)?['visits'];
  if (visits is! List) {
    return const <Stay>[];
  }
  return <Stay>[
    for (final visit in visits)
      if (visit case [final int arrived, final Object? stayed])
        (
          arrived: DateTime.fromMillisecondsSinceEpoch(arrived * 1000),
          stayed: stayed is int ? Duration(seconds: stayed) : null,
        ),
  ];
}

/// The visits of the [days] days up to today, counted in the viewer's own time zone.
@immutable
class VisitStats {
  const VisitStats._({
    required this.days,
    required this.perDay,
    required this.perHour,
    required this.averageStay,
  });

  /// Counts [stays] over the [days] calendar days that end with [now]'s.
  factory VisitStats.of(List<Stay> stays, DateTime now, {int days = 14}) {
    // Calendar dates as UTC midnights, so a daylight-saving day still counts as one.
    DateTime date(DateTime t) => DateTime.utc(t.year, t.month, t.day);
    final today = date(now);
    final perDay = List<int>.filled(days, 0);
    final perHour = List<int>.filled(24, 0);
    var stayed = Duration.zero;
    var left = 0;
    for (final stay in stays) {
      final back = today.difference(date(stay.arrived)).inDays;
      if (back < 0 || back >= days) {
        continue;
      }
      perDay[days - 1 - back]++;
      perHour[stay.arrived.hour]++;
      if (stay.stayed case final s?) {
        stayed += s;
        left++;
      }
    }
    return VisitStats._(
      days: days,
      perDay: perDay,
      perHour: perHour,
      averageStay: left == 0 ? null : stayed ~/ left,
    );
  }

  final int days;

  /// Visits per day, oldest first; the last is today.
  final List<int> perDay;

  /// Visits per hour of the day, 0 to 23.
  final List<int> perHour;

  /// Over the visits that have left; `null` while none has.
  final Duration? averageStay;

  int get today => perDay.last;
  int get total => perDay.fold(0, (a, b) => a + b);
}

/// A "Visits" button that opens the visits of the last two weeks per day and per hour, from
/// `/visits`, refreshed every [interval] while open.
class VisitStatsPanel extends StatefulWidget {
  const VisitStatsPanel({
    super.key,
    required this.fetch,
    this.interval = const Duration(minutes: 1),
    this.now = DateTime.now,
  });

  /// `/visits`'s body, or `null` when it does not answer.
  final Future<String?> Function() fetch;

  final Duration interval;

  /// The clock the days are counted to; a test sets its own.
  final DateTime Function() now;

  @override
  State<VisitStatsPanel> createState() => _VisitStatsPanelState();
}

class _VisitStatsPanelState extends State<VisitStatsPanel> {
  bool _open = false;
  VisitStats? _stats;
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
    final body = await fetchOrNull(widget.fetch);
    if (mounted && _open && body != null) {
      setState(() => _stats = VisitStats.of(staysFromJson(body), widget.now()));
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
      icon: Icon(_open ? Icons.expand_less : Icons.bar_chart),
      label: Text(l10n.visitStats),
    );
    final stats = _stats;
    if (!_open || stats == null) {
      return button;
    }
    final today = widget.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: stats.total == 0
                  ? Text(l10n.visitStatsNone(stats.days))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          l10n.visitStatsSummary(
                            stats.today,
                            stats.total,
                            stats.days,
                          ),
                        ),
                        if (stats.averageStay case final stay?)
                          Text(l10n.visitStatsAverageStay(stayMinutes(stay))),
                        Text(
                          l10n.visitStatsPerDay,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        _Bars(
                          counts: stats.perDay,
                          label: (i) =>
                              '${today.subtract(Duration(days: stats.days - 1 - i)).day}.',
                          labelEvery: 2,
                        ),
                        Text(
                          l10n.visitStatsPerHour,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        _Bars(
                          counts: stats.perHour,
                          label: (i) => '$i',
                          labelEvery: 6,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A bar per count, scaled to the largest; every [labelEvery]th bar is named below it.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.counts,
    required this.label,
    required this.labelEvery,
  });

  final List<int> counts;
  final String Function(int index) label;
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = math.max(1, counts.reduce(math.max));
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < counts.length; i++)
            Expanded(
              child: Tooltip(
                message: '${label(i)} ${counts[i]}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 72 * counts[i] / top,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      color: theme.colorScheme.primary,
                    ),
                    SizedBox(
                      height: 18,
                      child: i % labelEvery == 0
                          ? FittedBox(
                              child: Text(
                                label(i),
                                style: theme.textTheme.labelSmall,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
