import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:url_launcher/link.dart';

/// One visit from `/healthz`'s `cat.recent`: when the cat came, and how long it stayed once it had left.
class CatVisit {
  const CatVisit(this.arrived, [this.stayed]);

  final DateTime arrived;
  final Duration? stayed;
}

/// What the cat cam's `/healthz` says: its name, whether and when a cat was in view, and its visits.
class CatStatus {
  const CatStatus({
    required this.name,
    required this.inView,
    this.lastSeen,
    this.visits = 0,
    this.recent = const <CatVisit>[],
    this.clip,
  });

  final String name;
  final bool inView;
  final DateTime? lastSeen;

  /// Arrivals so far; each one replaces `/arrival.jpg`.
  final int visits;

  /// The latest visits, newest first.
  final List<CatVisit> recent;

  /// The arrival `/arrival.mp4` shows; a clip is encoded a few seconds after its arrival.
  final DateTime? clip;

  /// The clip is of the newest visit, not one before it still waiting to be replaced.
  bool get hasLatestClip =>
      clip != null && recent.isNotEmpty && clip == recent.first.arrived;

  /// `null` for anything but a cat cam's `/healthz` answer, so other hosts show nothing.
  static CatStatus? fromHealthz(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic> || json['ok'] != true) {
      return null;
    }
    final cat = json['cat'];
    if (cat is! Map<String, dynamic>) {
      return null;
    }
    final name = json['name'];
    final seconds = cat['last_seen'];
    final visits = cat['visits'];
    final recent = cat['recent'];
    final clip = cat['clip'];
    return CatStatus(
      name: name is String ? name : '',
      inView: cat['in_view'] == true,
      lastSeen: seconds is int
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          : null,
      visits: visits is int ? visits : 0,
      clip: clip is int
          ? DateTime.fromMillisecondsSinceEpoch(clip * 1000)
          : null,
      recent: <CatVisit>[
        if (recent is List)
          for (final visit in recent)
            if (visit is Map<String, dynamic> && visit['arrived'] is int)
              CatVisit(
                DateTime.fromMillisecondsSinceEpoch(
                  (visit['arrived'] as int) * 1000,
                ),
                visit['stayed_s'] is int
                    ? Duration(seconds: visit['stayed_s'] as int)
                    : null,
              ),
      ],
    );
  }
}

/// `14:32` for today, `Oct 11 14:32` for an earlier day, in [locale].
String formatLastSeen(DateTime when, DateTime now, String locale) {
  final today =
      when.year == now.year && when.month == now.month && when.day == now.day;
  return today
      ? DateFormat.Hm(locale).format(when)
      : DateFormat.MMMd(locale).add_Hm().format(when);
}

/// A stay in whole minutes, `<1` below one.
String stayMinutes(Duration stayed) =>
    stayed.inSeconds < 60 ? '<1' : '${(stayed.inSeconds / 60).round()}';

/// The arrival picture at [url], 240 px wide: the previous one until the next loads, nothing on an error.
Widget arrivalPicture(String url, String label) => Image.network(
  url,
  width: 240,
  semanticLabel: label,
  gaplessPlayback: true,
  errorBuilder: (_, _, _) => const SizedBox.shrink(),
);

/// The cat cam's name and its cat, polled from `/healthz`; with no cat cam behind the page, [fallbackName] alone.
class CatStatusLine extends StatefulWidget {
  const CatStatusLine({
    super.key,
    required this.fetch,
    required this.fallbackName,
    this.interval = const Duration(seconds: 5),
    this.arrivalImage = arrivalPicture,
  });

  /// The `/healthz` body, or `null` when nothing answers it.
  final Future<String?> Function() fetch;
  final String fallbackName;
  final Duration interval;

  /// Builds the last arrival's picture from its URL and label; tests swap the network out.
  final Widget Function(String url, String label) arrivalImage;

  @override
  State<CatStatusLine> createState() => _CatStatusLineState();
}

class _CatStatusLineState extends State<CatStatusLine> {
  CatStatus? _status;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(widget.interval, (_) => _poll());
  }

  Future<void> _poll() async {
    String? body;
    try {
      body = await widget.fetch();
    } on Object {
      body = null;
    }
    if (!mounted) {
      return;
    }
    setState(() => _status = body == null ? null : CatStatus.fromHealthz(body));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final named = status != null && status.name.isNotEmpty;
    final title = Text(
      named ? status.name : widget.fallbackName,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
    if (status == null) {
      return title;
    }
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final lastSeen = status.lastSeen;
    final IconData icon;
    final Color? color;
    final String text;
    if (status.inView) {
      (icon, color, text) = (Icons.pets, Colors.green, l10n.catInView);
    } else if (lastSeen != null) {
      final when = formatLastSeen(lastSeen, now, locale);
      (icon, color, text) = (Icons.history, null, l10n.catLastSeen(when));
    } else {
      (icon, color, text) = (
        Icons.visibility_off_outlined,
        null,
        l10n.catNotSeenYet,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        title,
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(icon, size: 18, color: color),
            // Flexible, so a long German line wraps on a narrow phone instead of overflowing.
            Flexible(child: Text(text)),
          ],
        ),
        if (status.recent.isNotEmpty)
          Text(
            l10n.catRecentVisits(
              status.recent
                  .take(3)
                  .map((visit) {
                    final time = formatLastSeen(visit.arrived, now, locale);
                    final stayed = visit.stayed;
                    return stayed == null
                        ? time
                        : l10n.catVisitStay(time, stayMinutes(stayed));
                  })
                  .join(' · '),
            ),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        // Keyed by the visit, which the cat cam counts after storing its frame; last_seen moves every run.
        if (status.visits > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: widget.arrivalImage(
              '/arrival.jpg?visit=${status.visits}',
              l10n.catLastArrival,
            ),
          ),
        if (status.hasLatestClip)
          Link(
            uri: Uri.parse('/arrival.mp4?visit=${status.visits}'),
            target: LinkTarget.blank,
            builder: (context, followLink) => TextButton.icon(
              onPressed: followLink,
              icon: const Icon(Icons.play_circle_outline),
              label: Text(l10n.catArrivalVideo),
            ),
          ),
      ],
    );
  }
}
