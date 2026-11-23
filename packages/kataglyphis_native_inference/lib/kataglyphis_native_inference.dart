import 'dart:async';

import 'kataglyphis_native_inference_platform_interface.dart';

export 'native_inference_channel.dart';

class KataglyphisNativeInference {
  Future<String?> getPlatformVersion() {
    return KataglyphisNativeInferencePlatform.instance.getPlatformVersion();
  }
}
