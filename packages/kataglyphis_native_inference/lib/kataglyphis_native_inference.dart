import 'dart:async';
import 'package:flutter/services.dart';
import 'kataglyphis_native_inference_platform_interface.dart';

class KataglyphisNativeInference {
  Future<String?> getPlatformVersion() {
    return KataglyphisNativeInferencePlatform.instance.getPlatformVersion();
  }
  static const MethodChannel _channel =
      MethodChannel('kataglyphis_native_inference');

  // example: add two ints via native code
  static Future<int> add(int a, int b) async {
    final res = await _channel.invokeMethod<int>('add', {'a': a, 'b': b});
    return res ?? 0;
  }
}
