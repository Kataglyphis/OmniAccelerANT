// lib/Pages/StreamPage/webrtc_view_stub.dart
import 'package:flutter/material.dart';

class WebRTCView extends StatelessWidget {
  final String signalingUrl;
  final String? producerIdToConsume;

  const WebRTCView({
    super.key,
    required this.signalingUrl,
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
