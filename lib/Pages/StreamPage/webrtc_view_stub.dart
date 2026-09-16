// lib/Pages/StreamPage/webrtc_view_stub.dart
import 'package:flutter/material.dart';

import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// Non-web stand-in for the real `WebRTCView`.
///
/// The constructor must stay signature-compatible with the web implementation
/// in `webrtc_view.dart`: `stream_page.dart` picks between the two with a
/// conditional import, so a mismatch is a compile error on exactly one of the
/// two build targets — which means the web lane is the only place it shows up.
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
