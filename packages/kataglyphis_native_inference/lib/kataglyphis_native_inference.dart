import 'dart:async';

import 'kataglyphis_native_inference_platform_interface.dart';
import 'native_inference_channel.dart';

export 'native_inference_channel.dart';

class KataglyphisNativeInference {
  Future<String?> getPlatformVersion() {
    return KataglyphisNativeInferencePlatform.instance.getPlatformVersion();
  }

  static Future<int> add(int a, int b) => NativeInferenceChannel.add(a, b);
}
