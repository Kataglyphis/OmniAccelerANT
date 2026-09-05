import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kataglyphis_native_inference/kataglyphis_native_inference_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelKataglyphisNativeInference platform = MethodChannelKataglyphisNativeInference();
  const MethodChannel channel = MethodChannel('kataglyphis_native_inference');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
