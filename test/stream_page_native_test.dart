// The native Stream page drives the C++ plugin over a MethodChannel; only a device ran these calls and their source fallback before.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_page.dart';
import 'package:omni_accelerant/main.dart';

import 'support/real_fonts.dart';

/// Stands in for the plugin: records every call, fails `setPipeline` for each source in [missing], and refuses every method in [refused].
class _FakePlugin {
  _FakePlugin({
    this.missing = const <String>{},
    this.createFails = false,
    this.refused = const <String>{},
  });

  final Set<String> missing;
  final bool createFails;
  final Set<String> refused;
  final List<MethodCall> calls = <MethodCall>[];

  List<String> get methods => <String>[
    for (final MethodCall c in calls) c.method,
  ];

  List<String> get pipelines => <String>[
    for (final MethodCall c in calls)
      if (c.method == 'setPipeline') c.arguments as String,
  ];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (refused.contains(call.method)) {
      throw PlatformException(
        code: 'refused',
        message: '${call.method} refused',
      );
    }
    switch (call.method) {
      case 'create':
        if (createFails) {
          throw PlatformException(code: 'texture', message: 'no registrar');
        }
        return 7;
      case 'setPipeline':
        final String source = (call.arguments as String).split(' ').first;
        if (missing.contains(source)) {
          throw PlatformException(
            code: 'pipeline_error',
            message: 'no element "$source"',
          );
        }
        return null;
      case 'diagnose':
        return 'fake diagnosis';
      default:
        return null;
    }
  }
}

/// Boots the app on its start page, the Stream page, with [plugin] behind the channel.
Future<void> _pumpApp(WidgetTester tester, _FakePlugin plugin) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    StreamPageState.channel,
    plugin.handle,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      StreamPageState.channel,
      null,
    ),
  );
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(const App());
    // The bootstrap reads its settings off the asset bundle, which is real I/O.
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the app, which stops the pipeline, and lets the timers it leaves run out.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadRealFonts);

  final TargetPlatformVariant linux = TargetPlatformVariant.only(
    TargetPlatform.linux,
  );

  testWidgets(
    'Linux without the Rust core creates a texture and plays the camera',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin();
      await _pumpApp(tester, plugin);

      expect(plugin.methods.take(3), <String>['create', 'setPipeline', 'play']);
      final List<Object?> size = plugin.calls.first.arguments as List<Object?>;
      expect(size, hasLength(2));
      expect(size.every((Object? v) => v is int && v > 0), isTrue);
      expect(plugin.pipelines.single, startsWith('v4l2src device=/dev/video0'));
      expect(
        plugin.pipelines.single,
        endsWith('appsink name=sink emit-signals=true sync=false'),
      );
      expect(find.byType(Texture), findsOneWidget);
      expect(find.text('Playing'), findsOneWidget);

      await _unmount(tester);
      expect(plugin.methods.last, 'stop');
    },
    variant: linux,
  );

  testWidgets(
    'a camera the pipeline cannot open falls back to the next source',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(missing: <String>{'v4l2src'});
      await _pumpApp(tester, plugin);

      expect(plugin.methods.take(5), <String>[
        'create',
        'setPipeline',
        'diagnose',
        'setPipeline',
        'play',
      ]);
      expect(plugin.pipelines.last, startsWith('autovideosrc'));
      expect(find.text('Playing'), findsOneWidget);
      expect(find.textContaining('No video source worked'), findsNothing);

      await _unmount(tester);
    },
    variant: linux,
  );

  testWidgets('with every source missing the error names all of them', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(
      missing: <String>{'v4l2src', 'autovideosrc', 'videotestsrc'},
    );
    await _pumpApp(tester, plugin);

    expect(plugin.pipelines.map((String p) => p.split(' ').first), <String>[
      'v4l2src',
      'autovideosrc',
      'videotestsrc',
    ]);
    expect(plugin.methods, isNot(contains('play')));
    expect(
      find.text(
        'No video source worked (tried: v4l2src, autovideosrc, videotestsrc). '
        'Last error: no element "videotestsrc"',
      ),
      findsOneWidget,
    );

    await _unmount(tester);
  }, variant: linux);

  testWidgets(
    'a texture the plugin cannot create is reported, and no pipeline is set',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(createFails: true);
      await _pumpApp(tester, plugin);

      expect(plugin.methods.first, 'create');
      expect(plugin.methods, isNot(contains('setPipeline')));
      expect(find.textContaining('Texture creation failed'), findsOneWidget);
      expect(find.byType(Texture), findsNothing);

      await _unmount(tester);
    },
    variant: linux,
  );

  testWidgets('the play/pause button pauses and resumes the pipeline', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await _pumpApp(tester, plugin);
    plugin.calls.clear();

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(plugin.methods, <String>['pause']);
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(plugin.methods, <String>['pause', 'play']);
    expect(find.text('Playing'), findsOneWidget);

    await _unmount(tester);
  }, variant: linux);

  testWidgets('the stop button stops the pipeline', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await _pumpApp(tester, plugin);
    plugin.calls.clear();

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(plugin.methods, <String>['stop']);
    expect(find.text('Paused'), findsOneWidget);

    await _unmount(tester);
  }, variant: linux);

  testWidgets('a stop the plugin refuses does not claim the stream stopped', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(refused: <String>{'stop'});
    await _pumpApp(tester, plugin);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Playing'), findsOneWidget);

    await _unmount(tester);
  }, variant: linux);

  testWidgets(
    'a source button stops the running pipeline and plays the chosen one',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin();
      await _pumpApp(tester, plugin);
      plugin.calls.clear();

      await tester.ensureVisible(find.text('SMPTE Pattern'));
      await tester.tap(find.text('SMPTE Pattern'));
      await tester.pump();
      expect(plugin.methods, <String>['stop', 'setPipeline', 'play']);
      expect(plugin.pipelines.single, contains('pattern=smpte'));
      expect(find.text('Playing'), findsOneWidget);

      await _unmount(tester);
    },
    variant: linux,
  );

  testWidgets('a colour button sends its RGB to the plugin', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await _pumpApp(tester, plugin);
    plugin.calls.clear();

    await tester.ensureVisible(find.text('Red'));
    await tester.tap(find.text('Red'));
    await tester.pump();
    expect(plugin.methods, <String>['setColor']);
    expect(plugin.calls.single.arguments, <int>[0xf2, 0x5d, 0x50]);

    await _unmount(tester);
  }, variant: linux);

  testWidgets(
    'a pause the plugin refuses is reported and the stream plays on',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(refused: <String>{'pause'});
      await _pumpApp(tester, plugin);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Play/Pause error: pause refused'), findsOneWidget);
      expect(find.text('Playing'), findsOneWidget);

      await _unmount(tester);
    },
    variant: linux,
  );

  testWidgets(
    'a pipeline error no other source would fix is reported without a fallback',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(refused: <String>{'setPipeline'});
      await _pumpApp(tester, plugin);

      expect(plugin.methods, <String>['create', 'setPipeline']);
      expect(find.text('Pipeline error: setPipeline refused'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await _unmount(tester);
    },
    variant: linux,
  );

  test('the variant leaves no platform override behind', () {
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
