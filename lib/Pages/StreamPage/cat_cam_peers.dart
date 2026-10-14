import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/Pages/StreamPage/cat_status.dart';
import 'package:omni_accelerant/utils/json_utils.dart';
import 'package:url_launcher/link.dart';

/// [url]'s picture, 160 px wide; nothing while the other cat cam does not answer.
Widget peerPicture(String url) => Image.network(
  url,
  width: 160,
  gaplessPlayback: true,
  errorBuilder: (_, _, _) => const SizedBox.shrink(),
);

/// The other cat cams this one names in `/healthz` (`peers`), each with its picture and its cat.
class CatCamPeers extends StatefulWidget {
  const CatCamPeers({
    super.key,
    required this.fetchOwn,
    required this.fetchFrom,
    this.interval = const Duration(seconds: 10),
    this.picture = peerPicture,
  });

  /// This cat cam's `/healthz`, which names the others.
  final Future<String?> Function() fetchOwn;

  /// A GET to another cat cam; it answers this page only when it lists this one as a peer too.
  final Future<String?> Function(String url) fetchFrom;
  final Duration interval;
  final Widget Function(String url) picture;

  @override
  State<CatCamPeers> createState() => _CatCamPeersState();
}

class _CatCamPeersState extends State<CatCamPeers> {
  List<String> _peers = const <String>[];

  /// The own cat cam answered: its peers come from its config, so it is not asked again.
  bool _knowsPeers = false;
  final Map<String, CatStatus?> _status = <String, CatStatus?>{};
  int _tick = 0;
  Timer? _timer;

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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    var peers = _peers;
    if (!_knowsPeers) {
      final own = await fetchOrNull(widget.fetchOwn);
      final status = own == null ? null : CatStatus.fromHealthz(own);
      if (status != null) {
        _knowsPeers = true;
        peers = status.peers;
        if (peers.isEmpty) {
          // A cat cam without peers has no overview to refresh.
          _timer?.cancel();
        }
      }
    }
    final answers = await Future.wait([
      for (final peer in peers)
        fetchOrNull(() => widget.fetchFrom('${_origin(peer)}/healthz')),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      _peers = peers;
      _tick++;
      _status
        ..clear()
        ..addAll({
          for (final (i, peer) in peers.indexed)
            peer: answers[i] == null
                ? null
                : CatStatus.fromHealthz(answers[i]!),
        });
    });
  }

  /// [peer] without a trailing slash, as an origin is written.
  static String _origin(String peer) =>
      peer.endsWith('/') ? peer.substring(0, peer.length - 1) : peer;

  @override
  Widget build(BuildContext context) {
    _visible = TickerMode.valuesOf(context).enabled;
    if (_peers.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Text(
          l10n.catOtherCameras,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final peer in _peers)
              _PeerCard(
                origin: _origin(peer),
                status: _status[peer],
                picture: widget.picture(
                  '${_origin(peer)}/snapshot.jpg?n=$_tick',
                ),
                line: switch (_status[peer]) {
                  final status? => catLine(l10n, status, now, locale),
                  null => (
                    Icons.cloud_off,
                    Colors.orange,
                    l10n.catPeerUnreachable,
                  ),
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.origin,
    required this.status,
    required this.picture,
    required this.line,
  });

  final String origin;
  final CatStatus? status;
  final Widget picture;
  final (IconData, Color?, String) line;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = line;
    final name = status?.name ?? '';
    return Link(
      uri: Uri.parse('$origin/#/stream'),
      target: LinkTarget.blank,
      builder: (context, followLink) => InkWell(
        onTap: followLink,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 176,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                if (status != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: picture,
                  ),
                Text(
                  name.isEmpty ? Uri.parse(origin).host : name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(icon, size: 16, color: color),
                    Flexible(
                      child: Text(
                        text,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
