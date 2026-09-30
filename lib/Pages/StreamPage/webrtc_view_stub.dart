import 'package:flutter/material.dart';

import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// Non-web stand-in; keep its constructor in step with `webrtc_view.dart`, or only the web lane breaks.
class WebRTCView extends StatelessWidget {
  final WebRTCSettings settings;
  final String? producerIdToConsume;

  const WebRTCView({
    super.key,
    required this.settings,
    this.producerIdToConsume,
  });

  @override
  Widget build(BuildContext context) {
    // Simple native fallback / placeholder
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: const Text(
        'WebRTC view is only available in the web build.\n'
        'This is a native fallback placeholder.',
        textAlign: TextAlign.center,
      ),
    );
  }
}
