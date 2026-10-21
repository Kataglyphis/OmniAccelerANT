// On Android and macOS the Stream page drives the plugin over a MethodChannel; only a device ran these calls and their source fallback before.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'support/real_fonts.dart';
import 'support/stream_page_app.dart';

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

/// Answers permission_handler's channel as Android would: the camera's status is [status].
class _FakePermissions {
  _FakePermissions(this.status);

  final PermissionStatus status;
  bool settingsOpened = false;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'requestPermissions':
        return <int, int>{
          for (final Object? p in call.arguments as List<Object?>)
            p! as int: status.index,
        };
      case 'openAppSettings':
        settingsOpened = true;
        return true;
      default:
        return status.index;
    }
  }
}

const MethodChannel _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

void main() {
  setUpAll(loadRealFonts);

  final TargetPlatformVariant macOS = TargetPlatformVariant.only(
    TargetPlatform.macOS,
  );

  testWidgets(
    'a camera the pipeline cannot open falls back to the next source',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(missing: <String>{'avfvideosrc'});
      await pumpStreamPageApp(tester, plugin.handle);

      expect(plugin.methods.take(5), <String>[
        'create',
        'setPipeline',
        'diagnose',
        'setPipeline',
        'play',
      ]);
      expect(plugin.pipelines.last, startsWith('videotestsrc'));
      expect(find.text('Playing'), findsOneWidget);
      expect(find.textContaining('No video source worked'), findsNothing);

      await unmountApp(tester);
    },
    variant: macOS,
  );

  testWidgets('with every source missing the error names all of them', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(
      missing: <String>{'avfvideosrc', 'videotestsrc'},
    );
    await pumpStreamPageApp(tester, plugin.handle);

    expect(plugin.pipelines.map((String p) => p.split(' ').first), <String>[
      'avfvideosrc',
      'videotestsrc',
    ]);
    expect(plugin.methods, isNot(contains('play')));
    expect(
      find.text(
        'No video source worked (tried: avfvideosrc, videotestsrc). '
        'Last error: no element "videotestsrc"',
      ),
      findsOneWidget,
    );

    await unmountApp(tester);
  }, variant: macOS);

  testWidgets(
    'a texture the plugin cannot create is reported, and no pipeline is set',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(createFails: true);
      await pumpStreamPageApp(tester, plugin.handle);

      expect(plugin.methods.first, 'create');
      expect(plugin.methods, isNot(contains('setPipeline')));
      expect(find.textContaining('Texture creation failed'), findsOneWidget);
      expect(find.byType(Texture), findsNothing);

      await unmountApp(tester);
    },
    variant: macOS,
  );

  testWidgets('the play/pause button pauses and resumes the pipeline', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpStreamPageApp(tester, plugin.handle);
    plugin.calls.clear();

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(plugin.methods, <String>['pause']);
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(plugin.methods, <String>['pause', 'play']);
    expect(find.text('Playing'), findsOneWidget);

    await unmountApp(tester);
  }, variant: macOS);

  testWidgets('the stop button stops the pipeline', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpStreamPageApp(tester, plugin.handle);
    plugin.calls.clear();

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(plugin.methods, <String>['stop']);
    expect(find.text('Paused'), findsOneWidget);

    await unmountApp(tester);
  }, variant: macOS);

  testWidgets('a stop the plugin refuses does not claim the stream stopped', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(refused: <String>{'stop'});
    await pumpStreamPageApp(tester, plugin.handle);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Playing'), findsOneWidget);

    await unmountApp(tester);
  }, variant: macOS);

  testWidgets(
    'a source button stops the running pipeline and plays the chosen one',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin();
      await pumpStreamPageApp(tester, plugin.handle);
      plugin.calls.clear();

      await tester.ensureVisible(find.text('SMPTE Pattern'));
      await tester.tap(find.text('SMPTE Pattern'));
      await tester.pump();
      expect(plugin.methods, <String>['stop', 'setPipeline', 'play']);
      expect(plugin.pipelines.single, contains('pattern=smpte'));
      expect(find.text('Playing'), findsOneWidget);

      await unmountApp(tester);
    },
    variant: macOS,
  );

  testWidgets('a colour button sends its RGB to the plugin', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpStreamPageApp(tester, plugin.handle);
    plugin.calls.clear();

    await tester.ensureVisible(find.text('Red'));
    await tester.tap(find.text('Red'));
    await tester.pump();
    expect(plugin.methods, <String>['setColor']);
    expect(plugin.calls.single.arguments, <int>[0xf2, 0x5d, 0x50]);

    await unmountApp(tester);
  }, variant: macOS);

  testWidgets(
    'a pause the plugin refuses is reported and the stream plays on',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(refused: <String>{'pause'});
      await pumpStreamPageApp(tester, plugin.handle);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Play/Pause error: pause refused'), findsOneWidget);
      expect(find.text('Playing'), findsOneWidget);

      await unmountApp(tester);
    },
    variant: macOS,
  );

  testWidgets(
    'a pipeline error no other source would fix is reported without a fallback',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(refused: <String>{'setPipeline'});
      await pumpStreamPageApp(tester, plugin.handle);

      expect(plugin.methods, <String>['create', 'setPipeline']);
      expect(find.text('Pipeline error: setPipeline refused'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await unmountApp(tester);
    },
    variant: macOS,
  );

  testWidgets('a pattern off the fallback chain reports its own error', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(missing: <String>{'videotestsrc'});
    await pumpStreamPageApp(tester, plugin.handle);
    plugin.calls.clear();

    await tester.ensureVisible(find.text('SMPTE Pattern'));
    await tester.tap(find.text('SMPTE Pattern'));
    await tester.pump();
    expect(plugin.methods, isNot(contains('diagnose')));
    expect(
      find.text('Pipeline error: no element "videotestsrc"'),
      findsOneWidget,
    );

    await unmountApp(tester);
  }, variant: macOS);

  group('Android', () {
    final TargetPlatformVariant android = TargetPlatformVariant.only(
      TargetPlatform.android,
    );

    Future<_FakePermissions> grant(
      WidgetTester tester,
      PermissionStatus status,
    ) async {
      final _FakePermissions permissions = _FakePermissions(status);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _permissionChannel,
        permissions.handle,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _permissionChannel,
          null,
        ),
      );
      return permissions;
    }

    testWidgets(
      'with the camera granted it plays the camera at the android size',
      (WidgetTester tester) async {
        await grant(tester, PermissionStatus.granted);
        final _FakePlugin plugin = _FakePlugin();
        await pumpStreamPageApp(tester, plugin.handle);

        expect(plugin.methods.take(3), <String>[
          'create',
          'setPipeline',
          'play',
        ]);
        // webrtc_settings.json's android block.
        expect(plugin.calls.first.arguments, <int>[320, 240]);
        expect(plugin.pipelines.single, startsWith('ahcsrc ! '));
        expect(find.byType(Texture), findsOneWidget);

        await unmountApp(tester);
      },
      variant: android,
    );

    testWidgets('the Camera2 button asks for ahc2src, not the test pattern', (
      WidgetTester tester,
    ) async {
      await grant(tester, PermissionStatus.granted);
      final _FakePlugin plugin = _FakePlugin();
      await pumpStreamPageApp(tester, plugin.handle);
      plugin.calls.clear();

      await tester.ensureVisible(find.text('Camera (ahc2src)'));
      await tester.tap(find.text('Camera (ahc2src)'));
      await tester.pump();
      expect(plugin.pipelines.single, startsWith('ahc2src ! '));

      await unmountApp(tester);
    }, variant: android);

    testWidgets('without the camera permission it says so and starts nothing', (
      WidgetTester tester,
    ) async {
      final _FakePermissions permissions = await grant(
        tester,
        PermissionStatus.denied,
      );
      final _FakePlugin plugin = _FakePlugin();
      await pumpStreamPageApp(tester, plugin.handle);

      expect(plugin.methods, isEmpty);
      expect(
        find.textContaining('Camera permission is required'),
        findsOneWidget,
      );
      expect(permissions.settingsOpened, isFalse);

      await unmountApp(tester);
    }, variant: android);

    testWidgets('a permanently denied camera opens the app settings', (
      WidgetTester tester,
    ) async {
      final _FakePermissions permissions = await grant(
        tester,
        PermissionStatus.permanentlyDenied,
      );
      final _FakePlugin plugin = _FakePlugin();
      await pumpStreamPageApp(tester, plugin.handle);

      expect(plugin.methods, isEmpty);
      expect(permissions.settingsOpened, isTrue);

      await unmountApp(tester);
    }, variant: android);

    testWidgets('a texture it cannot create falls back to the WebRTC preview', (
      WidgetTester tester,
    ) async {
      await grant(tester, PermissionStatus.granted);
      final _FakePlugin plugin = _FakePlugin(createFails: true);
      await pumpStreamPageApp(tester, plugin.handle);

      expect(
        find.textContaining('Falling back to WebRTC preview on Android'),
        findsOneWidget,
      );
      expect(find.byType(Texture), findsNothing);

      await unmountApp(tester);
    }, variant: android);
  });

  testWidgets(
    'macOS creates a texture and plays its camera through the plugin',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin();
      await pumpStreamPageApp(tester, plugin.handle);

      expect(plugin.methods.take(3), <String>['create', 'setPipeline', 'play']);
      final List<Object?> size = plugin.calls.first.arguments as List<Object?>;
      expect(size, hasLength(2));
      expect(size.every((Object? v) => v is int && v > 0), isTrue);
      expect(plugin.pipelines.single, startsWith('avfvideosrc '));
      expect(
        plugin.pipelines.single,
        endsWith('appsink name=sink emit-signals=true sync=false'),
      );
      expect(find.byType(Texture), findsOneWidget);
      expect(find.text('Playing'), findsOneWidget);
      expect(find.text('Mac Camera (avfvideosrc)'), findsOneWidget);

      await unmountApp(tester);
      expect(plugin.methods.last, 'stop');
    },
    variant: macOS,
  );

  testWidgets('a platform without a native path shows the WebRTC stand-in', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpStreamPageApp(tester, plugin.handle);

    expect(plugin.methods, isEmpty);
    expect(
      find.textContaining('WebRTC view is only available in the web build'),
      findsOneWidget,
    );

    await unmountApp(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  test('the variant leaves no platform override behind', () {
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
