// The address panel's texts per status: what the visitor reads for each refusal, and what the field takes.
import 'package:anthology/material_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_observant.dart';
import 'package:omni_accelerant/Pages/StreamPage/remote/remote_observant_panel.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

import 'support/fake_remote_browser.dart';

Future<RemoteObservantController> _pump(
  WidgetTester tester,
  FakeRemoteBrowser browser,
) async {
  final controller = RemoteObservantController(browser);
  await tester.pumpWidget(
    MaterialApp(
      builder: anthologyMaterialBuilder,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...anthologyLocalizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RemoteObservantPanel(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _connect(WidgetTester tester, String address) async {
  await tester.enterText(find.byType(TextField), address);
  await tester.tap(find.text('Connect'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without an address the page reads its own ObservANT', (
    tester,
  ) async {
    await _pump(tester, FakeRemoteBrowser());
    expect(find.textContaining('No address set'), findsOneWidget);
    expect(find.text('Check again'), findsNothing);
  });

  testWidgets('a saved address is asked on load and its camera named', (
    tester,
  ) async {
    final browser = FakeRemoteBrowser(saved: 'http://192.168.1.20:8080');
    await _pump(tester, browser);
    expect(browser.probed, hasLength(1));
    expect(
      find.text(
        'Connected to Futtertrog (ObservANT 2.3.4) at http://192.168.1.20:8080.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('The live picture, settings and questions'),
      findsOneWidget,
    );
    expect(find.text("Open the camera's own page"), findsOneWidget);
  });

  testWidgets('an invalid address shows its problem under the field', (
    tester,
  ) async {
    final browser = FakeRemoteBrowser();
    await _pump(tester, browser);
    await _connect(tester, 'catcam.local:8080');
    expect(find.text('Start with http:// or https://.'), findsOneWidget);
    expect(browser.saved, isNull);
  });

  testWidgets('an https page names mixed content and both ways out', (
    tester,
  ) async {
    final browser = FakeRemoteBrowser(page: 'https://app.example.org/app/');
    await _pump(tester, browser);
    await _connect(tester, 'http://192.168.1.20:8080');
    expect(find.textContaining('(mixed content)'), findsOneWidget);
    expect(find.textContaining('serve ObservANT over https'), findsOneWidget);
    expect(
      find.textContaining('open the app over http in your network'),
      findsOneWidget,
    );
    expect(find.text("Open the camera's own page"), findsOneWidget);
    expect(browser.probed, isEmpty);
  });

  testWidgets('a refused local-network permission says where to allow it', (
    tester,
  ) async {
    final browser = FakeRemoteBrowser(page: 'https://app.example.org/app/')
      ..permissions = [LocalNetworkPermission.denied];
    await _pump(tester, browser);
    await _connect(tester, 'https://192.168.1.20:8444');
    expect(
      find.textContaining('Local network access is blocked for this site'),
      findsOneWidget,
    );
    expect(find.textContaining('Site settings'), findsOneWidget);
  });

  testWidgets(
    'an unreachable camera names the page origin its peers must list',
    (tester) async {
      final browser = FakeRemoteBrowser(page: 'http://127.0.0.1:8000/app/')
        ..answer = (_) async => const ProbeNetworkError();
      await _pump(tester, browser);
      await _connect(tester, 'http://192.168.1.20:8080');
      expect(
        find.textContaining(
          'origin, http://127.0.0.1:8000, is in its peers list',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('local network access and the prompt'),
        findsNothing,
      );
    },
  );

  testWidgets('Clear forgets the address', (tester) async {
    final browser = FakeRemoteBrowser(saved: 'http://192.168.1.20:8080');
    await _pump(tester, browser);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(browser.saved, isNull);
    expect(find.textContaining('No address set'), findsOneWidget);
  });
}
