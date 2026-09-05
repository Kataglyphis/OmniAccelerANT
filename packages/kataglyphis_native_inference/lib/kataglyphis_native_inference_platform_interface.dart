import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'kataglyphis_native_inference_method_channel.dart';

abstract class KataglyphisNativeInferencePlatform extends PlatformInterface {
  /// Constructs a KataglyphisNativeInferencePlatform.
  KataglyphisNativeInferencePlatform() : super(token: _token);

  static final Object _token = Object();

  static KataglyphisNativeInferencePlatform _instance = MethodChannelKataglyphisNativeInference();

  /// The default instance of [KataglyphisNativeInferencePlatform] to use.
  ///
  /// Defaults to [MethodChannelKataglyphisNativeInference].
  static KataglyphisNativeInferencePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [KataglyphisNativeInferencePlatform] when
  /// they register themselves.
  static set instance(KataglyphisNativeInferencePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
