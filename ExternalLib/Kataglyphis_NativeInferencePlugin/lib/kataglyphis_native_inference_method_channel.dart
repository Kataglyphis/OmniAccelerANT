import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kataglyphis_native_inference_platform_interface.dart';

/// An implementation of [KataglyphisNativeInferencePlatform] that uses method channels.
class MethodChannelKataglyphisNativeInference extends KataglyphisNativeInferencePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('kataglyphis_native_inference');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
