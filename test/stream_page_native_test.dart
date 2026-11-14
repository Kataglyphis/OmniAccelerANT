// On Android the Stream page drives the plugin over a MethodChannel; only a device ran these calls and their source fallback before.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:anthology/Testing/real_fonts.dart';

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

  /// The answer to the next request; a test changes it, as a user who grants the camera later does.
  PermissionStatus status;
  bool settingsOpened = false;
  int requests = 0;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'requestPermissions':
        requests++;
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

/// Frames for the channel answers a tap starts; not pumpAndSettle, which a spinning progress indicator never lets end.
Future<void> pumpAWhile(WidgetTester tester) async {
  for (int frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const MethodChannel _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

void main() {
  setUpAll(loadAnthologyFonts);

  final TargetPlatformVariant android = TargetPlatformVariant.only(
    TargetPlatform.android,
  );

  /// Answers the camera permission as [status] for the rest of the test.
  Future<_FakePermissions> grant(
    WidgetTester tester, [
    PermissionStatus status = PermissionStatus.granted,
  ]) async {
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

  /// The page on Android with the camera granted, playing through [plugin].
  Future<void> pumpGranted(WidgetTester tester, _FakePlugin plugin) async {
    await grant(tester);
    await pumpStreamPageApp(tester, plugin.handle);
  }

  testWidgets(
    'a camera the pipeline cannot open falls back to the next source',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(missing: <String>{'ahcsrc'});
      await pumpGranted(tester, plugin);

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

      await unmountApp(tester);
    },
    variant: android,
  );

  testWidgets('with every source missing the error names all of them', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(
      missing: <String>{'ahcsrc', 'autovideosrc', 'videotestsrc'},
    );
    await pumpGranted(tester, plugin);

    expect(plugin.pipelines.map((String p) => p.split(' ').first), <String>[
      'ahcsrc',
      'autovideosrc',
      'videotestsrc',
    ]);
    expect(plugin.methods, isNot(contains('play')));
    expect(
      find.text(
        'No video source worked (tried: ahcsrc, autovideosrc, videotestsrc). '
        'Last error: no element "videotestsrc"',
      ),
      findsOneWidget,
    );

    await unmountApp(tester);
  }, variant: android);

  testWidgets('the play/pause button pauses and resumes the pipeline', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpGranted(tester, plugin);
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
  }, variant: android);

  testWidgets('the stop button stops the pipeline', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpGranted(tester, plugin);
    plugin.calls.clear();

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(plugin.methods, <String>['stop']);
    expect(find.text('Paused'), findsOneWidget);

    await unmountApp(tester);
  }, variant: android);

  testWidgets('play after stop sets the pipeline again, which stop released', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpGranted(tester, plugin);
    final String first = plugin.pipelines.single;
    plugin.calls.clear();

    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    // Android's plugin has no pipeline after stop, so a bare play there fails.
    expect(plugin.methods, <String>['stop', 'setPipeline', 'play']);
    expect(plugin.pipelines.single, first);
    expect(find.text('Playing'), findsOneWidget);

    // A pause keeps the pipeline: its play is the plain one.
    plugin.calls.clear();
    await tester.tap(find.text('Pause'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(plugin.methods, <String>['pause', 'play']);

    await unmountApp(tester);
  }, variant: android);

  testWidgets('a stop the plugin refuses does not claim the stream stopped', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(refused: <String>{'stop'});
    await pumpGranted(tester, plugin);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Playing'), findsOneWidget);

    await unmountApp(tester);
  }, variant: android);

  testWidgets(
    'a source button stops the running pipeline and plays the chosen one',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin();
      await pumpGranted(tester, plugin);
      plugin.calls.clear();

      await tester.ensureVisible(find.text('Test Pattern'));
      await tester.tap(find.text('Test Pattern'));
      await tester.pump();
      expect(plugin.methods, <String>['stop', 'setPipeline', 'play']);
      expect(plugin.pipelines.single, contains('pattern=ball'));
      expect(find.text('Playing'), findsOneWidget);

      await unmountApp(tester);
    },
    variant: android,
  );

  testWidgets(
    'a pause the plugin refuses is reported and the stream plays on',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(refused: <String>{'pause'});
      await pumpGranted(tester, plugin);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Play/Pause error: pause refused'), findsOneWidget);
      expect(find.text('Playing'), findsOneWidget);

      await unmountApp(tester);
    },
    variant: android,
  );

  testWidgets(
    'a pipeline error no other source would fix is reported without a fallback',
    (WidgetTester tester) async {
      final _FakePlugin plugin = _FakePlugin(refused: <String>{'setPipeline'});
      await pumpGranted(tester, plugin);

      expect(plugin.methods, <String>['create', 'setPipeline']);
      expect(find.text('Pipeline error: setPipeline refused'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await unmountApp(tester);
    },
    variant: android,
  );

  testWidgets('a source off the fallback chain reports its own error', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin(missing: <String>{'ahc2src'});
    await pumpGranted(tester, plugin);
    plugin.calls.clear();

    await tester.ensureVisible(find.text('Camera (ahc2src)'));
    await tester.tap(find.text('Camera (ahc2src)'));
    await tester.pump();
    expect(plugin.methods, isNot(contains('diagnose')));
    expect(find.text('Pipeline error: no element "ahc2src"'), findsOneWidget);

    await unmountApp(tester);
  }, variant: android);

  group('Android', () {
    testWidgets(
      'with the camera granted it plays the camera at the android size',
      (WidgetTester tester) async {
        await grant(tester);
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
      await grant(tester);
      final _FakePlugin plugin = _FakePlugin();
      await pumpStreamPageApp(tester, plugin.handle);
      plugin.calls.clear();

      await tester.ensureVisible(find.text('Camera (ahc2src)'));
      await tester.tap(find.text('Camera (ahc2src)'));
      await tester.pump();
      expect(plugin.pipelines.single, startsWith('ahc2src ! '));

      await unmountApp(tester);
    }, variant: android);

    testWidgets(
      'without the camera permission it says so once, and Retry asks again and starts once granted',
      (WidgetTester tester) async {
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
        // The denied permission showed "Error creating texture (null id)" beside its own text.
        expect(find.textContaining('texture'), findsNothing);
        expect(find.text('Open settings'), findsNothing);
        expect(permissions.settingsOpened, isFalse);

        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await pumpAWhile(tester);
        expect(permissions.requests, 2);
        expect(plugin.methods, isEmpty);

        permissions.status = PermissionStatus.granted;
        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await pumpAWhile(tester);
        expect(plugin.methods, contains('create'));
        expect(
          find.textContaining('Camera permission is required'),
          findsNothing,
        );

        await unmountApp(tester);
      },
      variant: android,
    );

    testWidgets(
      'a permanently denied camera offers the settings and opens them only on a tap; the return to the app retries',
      (WidgetTester tester) async {
        final _FakePermissions permissions = await grant(
          tester,
          PermissionStatus.permanentlyDenied,
        );
        final _FakePlugin plugin = _FakePlugin();
        await pumpStreamPageApp(tester, plugin.handle);

        expect(plugin.methods, isEmpty);
        expect(permissions.settingsOpened, isFalse);
        await tester.ensureVisible(find.text('Open settings'));
        await tester.tap(find.text('Open settings'));
        await pumpAWhile(tester);
        expect(permissions.settingsOpened, isTrue);

        permissions.status = PermissionStatus.granted;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpAWhile(tester);
        expect(permissions.requests, 2);
        expect(plugin.methods, contains('create'));

        await unmountApp(tester);
      },
      variant: android,
    );

    testWidgets(
      'a texture it cannot create says so with no WebRTC promise, and Retry creates again',
      (WidgetTester tester) async {
        await grant(tester);
        final _FakePlugin plugin = _FakePlugin(createFails: true);
        await pumpStreamPageApp(tester, plugin.handle);

        expect(
          find.textContaining('The video texture could not be created'),
          findsOneWidget,
        );
        expect(find.textContaining('WebRTC'), findsNothing);
        expect(find.textContaining('Camera permission'), findsNothing);
        expect(find.byType(Texture), findsNothing);

        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await pumpAWhile(tester);
        expect(plugin.methods.where((m) => m == 'create'), hasLength(2));

        await unmountApp(tester);
      },
      variant: android,
    );
  });

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

  testWidgets('macOS, no target, starts no plugin pipeline', (
    WidgetTester tester,
  ) async {
    final _FakePlugin plugin = _FakePlugin();
    await pumpStreamPageApp(tester, plugin.handle);

    expect(plugin.methods, isEmpty);
    expect(find.byType(Texture), findsNothing);

    await unmountApp(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('the variant leaves no platform override behind', () {
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
