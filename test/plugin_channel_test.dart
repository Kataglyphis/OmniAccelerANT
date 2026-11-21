// The plugin's channel table against the handlers the three platforms compile, read from their sources.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kataglyphis_native_inference/kataglyphis_native_inference.dart';

const String _plugin = 'packages/kataglyphis_native_inference';

const Map<PluginPlatform, String> _sources = {
  PluginPlatform.android:
      '$_plugin/android/src/main/kotlin/com/example/kataglyphis_native_inference/KataglyphisNativeInferencePlugin.kt',
  PluginPlatform.linux: '$_plugin/linux/kataglyphis_native_inference_plugin.cc',
  PluginPlatform.windows:
      '$_plugin/windows/kataglyphis_native_inference_plugin.cpp',
};

final Map<PluginPlatform, RegExp> _methodPatterns = {
  PluginPlatform.android: RegExp(r'^\s+"(\w+)" ->', multiLine: true),
  PluginPlatform.linux: RegExp(r'\{ "(\w+)", handle_\w+ \}'),
  PluginPlatform.windows: RegExp(r'method == "(\w+)"'),
};

final Map<PluginPlatform, RegExp> _errorPatterns = {
  PluginPlatform.android: RegExp(r'result\.error\("([^"]+)"'),
  PluginPlatform.linux: RegExp(r'fl_method_error_response_new\("([^"]+)"'),
  PluginPlatform.windows: RegExp(r'->Error\("([^"]+)"'),
};

final Map<PluginPlatform, RegExp> _channelPatterns = {
  PluginPlatform.android: RegExp(r'MethodChannel\([^,]+, "([^"]+)"\)'),
  PluginPlatform.linux: RegExp(r'"([^"]+)", FL_METHOD_CODEC'),
  PluginPlatform.windows: RegExp(r'"([^"]+)", &flutter::StandardMethodCodec'),
};

// A Windows checkout reads CRLF.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Set<String> _all(RegExp pattern, String source) =>
    pattern.allMatches(source).map((m) => m.group(1)!).toSet();

void main() {
  for (final PluginPlatform platform in PluginPlatform.values) {
    final String path = _sources[platform]!;

    test(
      'the ${platform.name} plugin answers the methods the table gives it',
      () {
        final Set<String> handled = _all(
          _methodPatterns[platform]!,
          _read(path),
        );
        final Set<String> listed = kNativeInferenceMethods
            .where((m) => m.errors.containsKey(platform))
            .map((m) => m.name)
            .toSet();
        expect(handled, isNotEmpty, reason: 'no handler found in $path');
        expect(handled, listed, reason: path);
      },
    );

    test(
      'the ${platform.name} plugin sends the error codes the table gives it',
      () {
        final Set<String> sent = _all(_errorPatterns[platform]!, _read(path));
        final Set<String> listed = kNativeInferenceMethods
            .expand((m) => m.errors[platform] ?? const <String>[])
            .toSet();
        expect(sent, listed, reason: path);
      },
    );

    test('the ${platform.name} plugin listens on the one channel name', () {
      expect(_all(_channelPatterns[platform]!, _read(path)), {
        kNativeInferenceChannelName,
      }, reason: path);
    });
  }

  test('app code calls the plugin through NativeInferenceChannel only', () {
    final List<String> named = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => _read(f.path).contains('MethodChannel('))
        .map((f) => f.path)
        .toList();
    expect(named, isEmpty);
  });

  test('a platform without the method is told apart from one with it', () {
    expect(pluginAnswers('add', PluginPlatform.windows), isTrue);
    expect(pluginAnswers('add', PluginPlatform.linux), isFalse);
    expect(pluginAnswers('add', PluginPlatform.android), isFalse);
    expect(pluginAnswers('add', null), isFalse);
    expect(pluginAnswers('noSuchMethod', PluginPlatform.windows), isFalse);
  });
}
