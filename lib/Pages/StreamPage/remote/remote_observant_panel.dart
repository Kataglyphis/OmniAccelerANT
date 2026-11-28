import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/link.dart';

import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/observant_address.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_observant.dart';

/// The Stream page's field for an explicit ObservANT address, with the connection's status and what blocks it.
class RemoteObservantPanel extends StatefulWidget {
  const RemoteObservantPanel({super.key, required this.controller});

  final RemoteObservantController controller;

  @override
  State<RemoteObservantPanel> createState() => _RemoteObservantPanelState();
}

class _RemoteObservantPanelState extends State<RemoteObservantPanel> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.origin?.toString() ?? '',
  );

  @override
  void initState() {
    super.initState();
    // A saved address is asked once per visit; the page's polls follow it without a click.
    if (widget.controller.origin != null &&
        widget.controller.status is ObservantOwnOrigin) {
      widget.controller.check();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _connect() => widget.controller.setAddress(_text.text);

  void _clear() {
    _text.clear();
    widget.controller.setAddress('');
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final TextTheme text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final ObservantConnectionStatus status = widget.controller.status;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(l10n.observantAddressTitle, style: text.titleMedium),
                  Text(l10n.observantAddressHelp, style: text.bodySmall),
                  TextField(
                    controller: _text,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      labelText: l10n.observantAddressLabel,
                      hintText: 'http://catcam.local:8080',
                      errorText: switch (status) {
                        ObservantFailed(
                          error: InvalidObservantAddress(:final problem),
                        ) =>
                          _problemText(l10n, problem),
                        _ => null,
                      },
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _connect,
                        child: Text(l10n.observantAddressConnect),
                      ),
                      if (widget.controller.origin != null) ...[
                        OutlinedButton(
                          onPressed: widget.controller.check,
                          child: Text(l10n.observantAddressCheckAgain),
                        ),
                        TextButton(
                          onPressed: _clear,
                          child: Text(l10n.observantAddressClear),
                        ),
                      ],
                    ],
                  ),
                  ..._statusLines(context, l10n, status),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _statusLines(
    BuildContext context,
    AppLocalizations l10n,
    ObservantConnectionStatus status,
  ) {
    final String address = widget.controller.origin?.toString() ?? '';
    return switch (status) {
      ObservantOwnOrigin() => [Text(l10n.observantAddressOwn)],
      ObservantChecking(:final prompting) => [
        Row(
          spacing: 8,
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            Expanded(
              child: Text(
                prompting
                    ? l10n.observantAddressPrompting(address)
                    : l10n.observantAddressChecking(address),
              ),
            ),
          ],
        ),
      ],
      ObservantConnected(:final name, :final version) => [
        _Notice(
          icon: Icons.check_circle_outline,
          color: Colors.green,
          lines: [
            l10n.observantAddressConnected(name, version, address),
            l10n.observantAddressRemoteLimits,
          ],
        ),
        _ownPageLink(l10n),
      ],
      ObservantFailed(error: InvalidObservantAddress()) => const [],
      ObservantFailed(:final error) => [
        _Notice(
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          lines: _errorLines(l10n, error, address),
        ),
        if (error is MixedContentBlocked) _ownPageLink(l10n),
      ],
    };
  }

  List<String> _errorLines(
    AppLocalizations l10n,
    ObservantConnectionError error,
    String address,
  ) => switch (error) {
    InvalidObservantAddress(:final problem) => [_problemText(l10n, problem)],
    MixedContentBlocked() => [
      l10n.observantMixedContentTitle,
      l10n.observantMixedContentBody(address),
      '• ${l10n.observantMixedContentFixHttps}',
      '• ${l10n.observantMixedContentFixHttp(address)}',
    ],
    LocalNetworkRefused() => [l10n.observantLocalNetworkRefused(address)],
    ObservantUnreachable(:final localNetwork) => [
      l10n.observantAddressUnreachable(address, _pageOrigin()),
      if (localNetwork) l10n.observantUnreachableLocalNetwork,
    ],
    ObservantTimedOut() => [
      l10n.observantTimedOut(address, '${widget.controller.timeout.inSeconds}'),
    ],
    ObservantRefused(:final status, :final body) => [
      l10n.observantRefusedStatus(address, '$status', body),
    ],
    NotAnObservant() => [l10n.observantNotObservant(address)],
  };

  /// The page's origin, which ObservANT's `read_origins` must list before it answers this page.
  String _pageOrigin() {
    final Uri page = widget.controller.page;
    return page.hasAuthority ? page.origin : page.toString();
  }

  Widget _ownPageLink(AppLocalizations l10n) {
    final Uri? origin = widget.controller.origin;
    if (origin == null) return const SizedBox.shrink();
    return Link(
      uri: origin.resolve('/#/stream'),
      target: LinkTarget.blank,
      builder: (context, followLink) => TextButton.icon(
        onPressed: followLink,
        icon: const Icon(Icons.open_in_new),
        label: Text(l10n.observantAddressOpenOwn),
      ),
    );
  }
}

String _problemText(AppLocalizations l10n, ObservantAddressProblem problem) =>
    switch (problem) {
      ObservantAddressProblem.notUrl => l10n.observantAddressNotUrl,
      ObservantAddressProblem.scheme => l10n.observantAddressScheme,
      ObservantAddressProblem.noHost => l10n.observantAddressNoHost,
      ObservantAddressProblem.credentials => l10n.observantAddressCredentials,
      ObservantAddressProblem.path => l10n.observantAddressPath,
      ObservantAddressProblem.port => l10n.observantAddressPort,
    };

/// A tinted box of lines under one icon.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.lines});

  final IconData icon;
  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Icon(icon, color: color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [for (final String line in lines) Text(line)],
            ),
          ),
        ],
      ),
    );
  }
}
