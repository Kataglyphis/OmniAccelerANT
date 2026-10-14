import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/utils/json_utils.dart';
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
    this.clips = const <DateTime>[],
    this.problem,
    this.peers = const <String>[],
  });

  /// The other cat cams' origins, as `catcam.toml` lists them, for the overview.
  final List<String> peers;

  /// Why the camera is not ok, in the cat cam's words; `null` while it delivers.
  final String? problem;

  final String name;
  final bool inView;
  final DateTime? lastSeen;

  /// Arrivals so far; each one replaces `/arrival.jpg`.
  final int visits;

  /// The latest visits, newest first.
  final List<CatVisit> recent;

  /// The arrival `/arrival.mp4` shows; a clip is encoded a few seconds after its arrival.
  final DateTime? clip;

  /// Every arrival whose clip `/arrival.mp4?t=` still serves, newest first.
  final List<DateTime> clips;

  /// The clip is of the newest visit, not one before it still waiting to be replaced.
  bool get hasLatestClip =>
      clip != null && recent.isNotEmpty && clip == recent.first.arrived;

  /// `null` for anything but a cat cam's `/healthz` answer, so other hosts show nothing; one that is
  /// not ok still is one, with its [problem].
  static CatStatus? fromHealthz(String body) {
    final json = decodeJsonObject(body);
    final ok = json?['ok'];
    if (json == null || ok is! bool) {
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
    final clips = cat['clips'];
    final problem = json['problem'];
    final peers = json['peers'];
    return CatStatus(
      peers: <String>[
        if (peers is List)
          for (final peer in peers)
            if (peer is String) peer,
      ],
      problem: ok ? null : (problem is String ? problem : ''),
      name: name is String ? name : '',
      inView: cat['in_view'] == true,
      lastSeen: seconds is int
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          : null,
      visits: visits is int ? visits : 0,
      clip: clip is int
          ? DateTime.fromMillisecondsSinceEpoch(clip * 1000)
          : null,
      clips: <DateTime>[
        if (clips is List)
          for (final t in clips)
            if (t is int) DateTime.fromMillisecondsSinceEpoch(t * 1000),
      ],
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

/// What [status] says about the cat in one line, with its icon and colour.
(IconData, Color?, String) catLine(
  AppLocalizations l10n,
  CatStatus status,
  DateTime now,
  String locale,
) {
  final lastSeen = status.lastSeen;
  if (status.inView) {
    return (Icons.pets, Colors.green, l10n.catInView);
  }
  if (lastSeen != null) {
    final when = formatLastSeen(lastSeen, now, locale);
    return (Icons.history, null, l10n.catLastSeen(when));
  }
  return (Icons.visibility_off_outlined, null, l10n.catNotSeenYet);
}

/// `14:32` for today, `Oct 11 14:32` for an earlier day, in [locale].
String formatLastSeen(DateTime when, DateTime now, String locale) {
  final today =
      when.year == now.year && when.month == now.month && when.day == now.day;
  return today
      ? DateFormat.Hm(locale).format(when)
      : DateFormat.MMMd(locale).add_Hm().format(when);
}

/// One visit as the status line lists it: `14:32 (3 min)`, or the time alone while it goes on.
String visitText(
  AppLocalizations l10n,
  CatVisit visit,
  DateTime now,
  String locale,
) {
  final time = formatLastSeen(visit.arrived, now, locale);
  final stayed = visit.stayed;
  return stayed == null ? time : l10n.catVisitStay(time, stayMinutes(stayed));
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

  /// When a cat cam that answered stopped answering; `null` while it answers.
  DateTime? _unreachableSince;

  /// The whole visit log shows, not only the three latest.
  bool _allVisits = false;

  /// False while another tab of the bottom bar shows: go_router keeps this page alive behind it.
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(widget.interval, (_) {
      if (_visible) {
        _poll();
      }
    });
  }

  Future<void> _poll() async {
    final body = await fetchOrNull(widget.fetch);
    if (!mounted) {
      return;
    }
    setState(() {
      if (body == null && _status != null) {
        // It answered before: say since when it is gone, and keep what it said.
        _unreachableSince ??= DateTime.now();
        return;
      }
      _unreachableSince = null;
      _status = body == null ? null : CatStatus.fromHealthz(body);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      // Back in view: show the cat as it is now, not as it was when the page was left.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _poll();
        }
      });
    }
    _visible = visible;
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
    final (icon, color, text) = switch (_unreachableSince) {
      final since? => (
        Icons.cloud_off,
        Colors.orange,
        l10n.catCamUnreachable(formatLastSeen(since, now, locale)),
      ),
      null => catLine(l10n, status, now, locale),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        title,
        if (status.problem case final problem? when _unreachableSince == null)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              const Icon(Icons.warning_amber, size: 18, color: Colors.orange),
              Flexible(child: Text(l10n.catCamProblem(problem))),
            ],
          ),
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
                  .take(_allVisits ? status.recent.length : 3)
                  .map((visit) => visitText(l10n, visit, now, locale))
                  .join(' · '),
            ),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        if (status.recent.length > 3)
          TextButton(
            onPressed: () => setState(() => _allVisits = !_allVisits),
            child: Text(
              _allVisits
                  ? l10n.catFewerVisits
                  : l10n.catAllVisits(status.recent.length),
            ),
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
            // Its arrival's own clip, even after a newer visit replaces the picture above.
            uri: Uri.parse(
              '/arrival.mp4?t=${status.clip!.millisecondsSinceEpoch ~/ 1000}',
            ),
            target: LinkTarget.blank,
            builder: (context, followLink) => TextButton.icon(
              onPressed: followLink,
              icon: const Icon(Icons.play_circle_outline),
              label: Text(l10n.catArrivalVideo),
            ),
          ),
        // The other kept clips, so an earlier visit's video stays a tap away after a newer one.
        if (status.clips.any(
          (t) => !(status.hasLatestClip && t == status.clip),
        ))
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.catEarlierVideos,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final t in status.clips)
                if (!(status.hasLatestClip && t == status.clip))
                  Link(
                    uri: Uri.parse(
                      '/arrival.mp4?t=${t.millisecondsSinceEpoch ~/ 1000}',
                    ),
                    target: LinkTarget.blank,
                    builder: (context, followLink) => InkWell(
                      onTap: followLink,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 2,
                          children: [
                            // The arrival's own picture, so the right video is found at a glance.
                            ExcludeSemantics(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 96,
                                  height: 72,
                                  // The film icon shows until the picture covers it, and stays where none is kept.
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ColoredBox(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        child: const Icon(Icons.movie_outlined),
                                      ),
                                      FittedBox(
                                        fit: BoxFit.cover,
                                        clipBehavior: Clip.hardEdge,
                                        child: widget.arrivalImage(
                                          '/arrival.jpg?t=${t.millisecondsSinceEpoch ~/ 1000}',
                                          '',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow, size: 16),
                                // A screen reader skips the icon; the time alone would not say what plays.
                                Text(
                                  formatLastSeen(t, now, locale),
                                  semanticsLabel: l10n.catVideoFrom(
                                    formatLastSeen(t, now, locale),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}
