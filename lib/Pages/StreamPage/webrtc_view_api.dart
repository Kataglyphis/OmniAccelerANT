import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:omni_accelerant/Pages/StreamPage/stream_controller.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// How a page builds the stream view; the web and the native file each hold a constant of this type.
typedef WebRTCViewBuilder = Widget Function({
  Key? key,
  required WebRTCSettings settings,
  String? producerIdToConsume,
});

/// Where the stats panel reads the browser's numbers; `null` when there are none.
typedef PlaybackStatsSource = ValueListenable<PlaybackStats?>? Function();
