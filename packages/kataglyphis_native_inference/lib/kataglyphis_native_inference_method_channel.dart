import 'package:flutter/foundation.dart';

import 'kataglyphis_native_inference_platform_interface.dart';
import 'native_inference_channel.dart';

/// An implementation of [KataglyphisNativeInferencePlatform] that uses method channels.
class MethodChannelKataglyphisNativeInference
    extends KataglyphisNativeInferencePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = NativeInferenceChannel.channel;

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
