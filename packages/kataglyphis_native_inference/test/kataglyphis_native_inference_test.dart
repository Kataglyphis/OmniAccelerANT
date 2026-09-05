import 'package:flutter_test/flutter_test.dart';
import 'package:kataglyphis_native_inference/kataglyphis_native_inference.dart';
import 'package:kataglyphis_native_inference/kataglyphis_native_inference_platform_interface.dart';
import 'package:kataglyphis_native_inference/kataglyphis_native_inference_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockKataglyphisNativeInferencePlatform
    with MockPlatformInterfaceMixin
    implements KataglyphisNativeInferencePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final KataglyphisNativeInferencePlatform initialPlatform = KataglyphisNativeInferencePlatform.instance;

  test('$MethodChannelKataglyphisNativeInference is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelKataglyphisNativeInference>());
  });

  test('getPlatformVersion', () async {
    KataglyphisNativeInference kataglyphisNativeInferencePlugin = KataglyphisNativeInference();
    MockKataglyphisNativeInferencePlatform fakePlatform = MockKataglyphisNativeInferencePlatform();
    KataglyphisNativeInferencePlatform.instance = fakePlatform;

    expect(await kataglyphisNativeInferencePlugin.getPlatformVersion(), '42');
  });
}
