import 'dart:async';

import 'package:anthology/Pages/Footer/default_footer_config.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/Pages/Home/default_home_config.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/app_settings.dart';
import 'package:anthology/constants.dart';
import 'package:anthology/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/DevicePage/device_page.dart';
import 'package:omni_accelerant/Pages/DevicePage/esp32_controller.dart';
import 'package:omni_accelerant/Pages/omni_screen_configurations.dart';
import 'package:omni_accelerant/src/rust/api/esp32.dart';

import 'support/fake_esp32_api.dart';

/// The Device page alone, footer off, over [controller] (or its own Rust one when null).
Future<void> _pumpDevicePage(
  WidgetTester tester, {
  Esp32Controller? controller,
}) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final UserSettings userSettings = UserSettings(
    socialMediaLinksConfig: const {},
    businessEmail: 'test@example.com',
    myQuotation: '',
    firstName: 'Jane',
    lastName: 'Doe',
    aboutMeFileDe: 'about_de.md',
    aboutMeFileEn: 'about_en.md',
    assetPathImgOfMe: 'me.jpg',
  );
  final DefaultFooterConfig footerConfig = DefaultFooterConfig();
  final AppAttributes appAttributes = AppAttributes(
    footerConfig: footerConfig,
    homeConfig: DefaultHomeConfig(),
    appSettings: AppSettings(
      appNameDe: 'OmniAccelerANT',
      appNameEn: 'OmniAccelerANT',
      appTitleDe: 'OmniAccelerANT',
      appTitleEn: 'OmniAccelerANT',
      disableFooter: true,
    ),
    userSettings: userSettings,
    screenConfigurations: OmniScreenConfigurations(blogPageConfigs: const []),
    railAnimation: CurvedAnimation(
      parent: kAlwaysCompleteAnimation,
      curve: Curves.linear,
    ),
    showMediumSizeLayout: false,
    showLargeSizeLayout: false,
    colorSelected: ColorSeed.baseColor,
    useLightMode: true,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DevicePage(
          appAttributes: appAttributes,
          footer: Footer(
            footerPagesConfigs: const [],
            userSettings: userSettings,
            footerConfig: footerConfig,
          ),
          controller: controller,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A page over a fake bridge with an ESP32 board and an unrelated adapter plugged in.
Future<(FakeEsp32Api, Esp32Controller)> _pumpWithPorts(
  WidgetTester tester,
) async {
  final FakeEsp32Api api = FakeEsp32Api()
    ..ports = <Esp32Device>[
      esp32Port('/dev/ttyACM0'),
      esp32Port('/dev/ttyUSB0', espressif: false),
      const Esp32Device(
        path: '/dev/ttyS0',
        vendorId: 0,
        productId: 0,
        espressif: false,
      ),
    ];
  final Esp32Controller controller = Esp32Controller(api: api);
  addTearDown(controller.dispose);
  await _pumpDevicePage(tester, controller: controller);
  return (api, controller);
}

/// Connects through the page's button and lets [hello] arrive.
Future<void> _connect(
  WidgetTester tester,
  FakeEsp32Api api,
  Esp32Event hello,
) async {
  await tester.tap(find.text('Connect'));
  await tester.pump();
  api.events.add(hello);
  await tester.pump();
}

/// The value an `_Info` tile shows under [label].
String _info(WidgetTester tester, String label) {
  final Finder tile = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  return tester
      .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
      .last
      .data!;
}

IconButton _rescan(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(
    of: find.byIcon(Icons.refresh),
    matching: find.byType(IconButton),
  ),
);

/// FilledButton.icon builds a private subclass, which find.byType does not match.
final Finder _connectButton = find.ancestor(
  of: find.text('Connect'),
  matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
);

String _chip(WidgetTester tester) {
  final Chip chip = tester.widget<Chip>(find.byType(Chip));
  return (chip.label as Text).data!;
}

Color? _swatch(WidgetTester tester) {
  final Container swatch = tester.widget<Container>(
    find.byWidgetPredicate(
      (Widget w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).borderRadius ==
              BorderRadius.circular(6),
    ),
  );
  return (swatch.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('lists the ports with the board preselected and labelled', (
    WidgetTester tester,
  ) async {
    final (_, Esp32Controller controller) = await _pumpWithPorts(tester);

    expect(controller.selectedPath, '/dev/ttyACM0');
    expect(
      find.text(
        'ESP32 · /dev/ttyACM0 · USB JTAG/serial debug unit · E8:06:90:9D:3E:78',
      ),
      findsOneWidget,
    );
    expect(
      find.text('1 Espressif board(s) of 3 serial port(s).'),
      findsOneWidget,
    );
    expect(_chip(tester), 'Disconnected');
    expect(find.text('Board'), findsNothing);
    expect(find.text('Status LED'), findsNothing);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('/dev/ttyS0 · Serial port'), findsOneWidget);
    await tester.tap(find.text('/dev/ttyUSB0 · FT232R USB UART').last);
    await tester.pumpAndSettle();

    expect(controller.selectedPath, '/dev/ttyUSB0');
    expect(find.text('/dev/ttyUSB0 · FT232R USB UART'), findsOneWidget);
  });

  testWidgets('without ports it says how to attach the board', (
    WidgetTester tester,
  ) async {
    final FakeEsp32Api api = FakeEsp32Api();
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await _pumpDevicePage(tester, controller: controller);

    expect(find.text('No serial port found'), findsOneWidget);
    expect(
      find.textContaining('Attach the board with its USB port and rescan.'),
      findsOneWidget,
    );

    api.ports = <Esp32Device>[esp32Port('/dev/ttyACM0')];
    await tester.tap(find.byTooltip('Rescan serial ports'));
    await tester.pump();
    expect(
      find.text('1 Espressif board(s) of 1 serial port(s).'),
      findsOneWidget,
    );
  });

  testWidgets('the controls are disabled while the ports are listed', (
    WidgetTester tester,
  ) async {
    final FakeEsp32Api api = FakeEsp32Api()
      ..pendingList = Completer<List<Esp32Device>>();
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await _pumpDevicePage(tester, controller: controller);

    expect(_chip(tester), 'Connecting…');
    expect(_rescan(tester).onPressed, isNull);
    expect(tester.widget<ButtonStyleButton>(_connectButton).onPressed, isNull);
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged,
      isNull,
    );

    api.pendingList!.complete(<Esp32Device>[esp32Port('/dev/ttyACM0')]);
    await tester.pumpAndSettle();
    expect(_chip(tester), 'Disconnected');
    expect(_rescan(tester).onPressed, isNotNull);
    expect(
      tester.widget<ButtonStyleButton>(_connectButton).onPressed,
      isNotNull,
    );
  });

  testWidgets('a failed listing shows the error and the error chip', (
    WidgetTester tester,
  ) async {
    final FakeEsp32Api api = FakeEsp32Api()..listError = StateError('udev');
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await _pumpDevicePage(tester, controller: controller);

    expect(
      find.text('Could not list serial ports: Bad state: udev'),
      findsOneWidget,
    );
    expect(_chip(tester), 'Error');
  });

  testWidgets('an unavailable bridge shows the notice instead of the port', (
    WidgetTester tester,
  ) async {
    final Esp32Controller controller = Esp32Controller(
      api: FakeEsp32Api(availableValue: false),
    );
    addTearDown(controller.dispose);
    await _pumpDevicePage(tester, controller: controller);

    expect(find.textContaining('built for the desktop app'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('without an injected controller it owns one and disposes it', (
    WidgetTester tester,
  ) async {
    await _pumpDevicePage(tester);
    // No RustLib under flutter test, so the page's own controller reports the bridge unavailable.
    expect(find.textContaining('built for the desktop app'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a connected board shows its telemetry, formatted', (
    WidgetTester tester,
  ) async {
    final (FakeEsp32Api api, _) = await _pumpWithPorts(tester);
    await _connect(
      tester,
      api,
      esp32Event(
        'hello',
        firmware: '0.1.0',
        mac: 'E8:06:90:9D:3E:78',
        uptimeMs: 5000,
      ),
    );

    expect(_chip(tester), 'Connected');
    expect(find.text('Disconnect'), findsOneWidget);
    expect(_info(tester, 'Firmware'), '0.1.0');
    expect(_info(tester, 'MAC'), 'E8:06:90:9D:3E:78');
    expect(_info(tester, 'Uptime'), '5s');
    expect(_info(tester, 'Free heap'), '—');
    expect(_info(tester, 'Chip temperature'), '—');
    expect(_info(tester, 'BOOT button'), 'released');
    expect(_info(tester, 'Latest detections'), '0');
    expect(find.text('On-device camera'), findsNothing);

    api.events.add(
      esp32Event(
        'telemetry',
        uptimeMs: 125000,
        freeHeap: 4096,
        temperatureCentiC: 4210,
        flag: true,
        detectionCount: 3,
      ),
    );
    await tester.pump();
    expect(_info(tester, 'Uptime'), '2m 5s');
    expect(_info(tester, 'Free heap'), '4.0 KiB');
    expect(_info(tester, 'Chip temperature'), '42.1 °C');
    expect(_info(tester, 'BOOT button'), 'held down');
    expect(_info(tester, 'Latest detections'), '3');

    api.events.add(esp32Event('telemetry', uptimeMs: 3723000, freeHeap: 0));
    await tester.pump();
    expect(_info(tester, 'Uptime'), '1h 2m');
    expect(_info(tester, 'Free heap'), '—');
    expect(_info(tester, 'Chip temperature'), '—');
  });

  testWidgets('the on-device camera tile appears with the first camera event', (
    WidgetTester tester,
  ) async {
    final (FakeEsp32Api api, _) = await _pumpWithPorts(tester);
    await _connect(tester, api, esp32Event('hello'));

    api.events.add(esp32Event('camera', value: 0));
    await tester.pump();
    expect(_info(tester, 'On-device camera'), 'no hits yet');

    api.events.add(esp32Event('camera', value: 2, scorePermille: 934));
    await tester.pump();
    expect(_info(tester, 'On-device camera'), '2 hit(s), 93 %');
  });

  testWidgets('ping sends a ping and shows the last pong id', (
    WidgetTester tester,
  ) async {
    final (FakeEsp32Api api, _) = await _pumpWithPorts(tester);
    await _connect(tester, api, esp32Event('hello'));

    await tester.tap(find.text('Ping'));
    expect(api.pings, 1);

    api.events.add(esp32Event('pong', value: 7));
    await tester.pump();
    expect(find.text('Ping (last id 7)'), findsOneWidget);
  });

  testWidgets('the LED buttons send the slider colour', (
    WidgetTester tester,
  ) async {
    final (FakeEsp32Api api, _) = await _pumpWithPorts(tester);
    await _connect(tester, api, esp32Event('hello'));
    expect(_swatch(tester), const Color.fromARGB(255, 0, 0, 255));

    await tester.drag(find.byType(Slider).at(0), const Offset(2000, 0));
    await tester.drag(find.byType(Slider).at(2), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(_swatch(tester), const Color.fromARGB(255, 255, 0, 0));

    await tester.tap(find.text('Apply'));
    await tester.tap(find.text('Pulse 0.5 s'));

    await tester.drag(find.byType(Slider).at(1), const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(_swatch(tester), const Color.fromARGB(255, 255, 255, 0));
    await tester.tap(find.text('Off'));
    await tester.tap(find.text('Apply'));

    expect(api.leds, <(int, int, int, int)>[
      (255, 0, 0, 0),
      (255, 0, 0, 500),
      (0, 0, 0, 0),
      (255, 255, 0, 0),
    ], reason: 'Off sends black but keeps the sliders');
  });

  testWidgets('disconnect hides the board and returns to the port picker', (
    WidgetTester tester,
  ) async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _pumpWithPorts(
      tester,
    );
    await _connect(tester, api, esp32Event('hello'));
    expect(find.text('Board'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    // StreamSubscription.cancel answers with a root-zone future, which only a real event-loop turn completes.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(api.disconnects, 1);
    expect(controller.connected, isFalse);
    expect(_chip(tester), 'Disconnected');
    expect(find.text('Board'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
  });
}
