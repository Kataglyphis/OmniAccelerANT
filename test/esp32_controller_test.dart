import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/DevicePage/esp32_controller.dart';
import 'package:omni_accelerant/src/rust/api/esp32.dart';

import 'support/fake_esp32_api.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A controller already linked to a board on /dev/ttyACM0.
Future<(FakeEsp32Api, Esp32Controller)> _connected() async {
  final FakeEsp32Api api = FakeEsp32Api();
  api.ports = <Esp32Device>[esp32Port('/dev/ttyACM0')];
  final Esp32Controller controller = Esp32Controller(api: api);
  addTearDown(controller.dispose);
  await controller.refresh();
  await controller.connect();
  api.events.add(esp32Event('hello'));
  await _settle();
  return (api, controller);
}

void main() {
  test('refresh selects the first port and preselects it', () async {
    final FakeEsp32Api api = FakeEsp32Api();
    api.ports = <Esp32Device>[
      esp32Port('/dev/ttyUSB0', espressif: false),
      esp32Port('/dev/ttyACM0'),
    ];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.devices, hasLength(2));
    expect(controller.selectedPath, '/dev/ttyACM0');
    expect(controller.error, isNull);
  });

  test(
    'refresh falls back to the first port when no board is Espressif',
    () async {
      final FakeEsp32Api api = FakeEsp32Api();
      api.ports = <Esp32Device>[
        esp32Port('/dev/ttyUSB0', espressif: false),
        esp32Port('/dev/ttyUSB1', espressif: false),
      ];
      final Esp32Controller controller = Esp32Controller(api: api);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.selectedPath, '/dev/ttyUSB0');
    },
  );

  test('refresh keeps a chosen port that is still plugged in', () async {
    final FakeEsp32Api api = FakeEsp32Api();
    api.ports = <Esp32Device>[
      esp32Port('/dev/ttyUSB0', espressif: false),
      esp32Port('/dev/ttyACM0'),
    ];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await controller.refresh();
    int notified = 0;
    controller.addListener(() => notified++);

    controller.select('/dev/ttyUSB0');
    expect(controller.selectedPath, '/dev/ttyUSB0');
    expect(notified, 1);

    await controller.refresh();
    expect(controller.selectedPath, '/dev/ttyUSB0');
  });

  test('refresh drops the selection once the last port is gone', () async {
    final FakeEsp32Api api = FakeEsp32Api();
    api.ports = <Esp32Device>[esp32Port('/dev/ttyACM0')];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.selectedPath, '/dev/ttyACM0');

    api.ports = const <Esp32Device>[];
    await controller.refresh();

    expect(controller.devices, isEmpty);
    expect(controller.selectedPath, isNull);
  });

  test(
    'a failed port listing is reported and ends the loading state',
    () async {
      final FakeEsp32Api api = FakeEsp32Api()..listError = StateError('udev');
      final Esp32Controller controller = Esp32Controller(api: api);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.error, 'Could not list serial ports: Bad state: udev');
      expect(controller.loading, isFalse);
    },
  );

  test('refresh is loading until the ports arrive', () async {
    final FakeEsp32Api api = FakeEsp32Api()
      ..pendingList = Completer<List<Esp32Device>>();
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    final Future<void> refreshing = controller.refresh();
    expect(controller.loading, isTrue);

    api.pendingList!.complete(<Esp32Device>[esp32Port('/dev/ttyACM0')]);
    await refreshing;
    expect(controller.loading, isFalse);
    expect(controller.selectedPath, '/dev/ttyACM0');
  });

  test('a listing that finishes after dispose does not notify', () async {
    final FakeEsp32Api api = FakeEsp32Api()
      ..pendingList = Completer<List<Esp32Device>>();
    final Esp32Controller controller = Esp32Controller(api: api);

    final Future<void> refreshing = controller.refresh();
    controller.dispose();
    api.pendingList!.complete(<Esp32Device>[esp32Port('/dev/ttyACM0')]);

    // A disposed ChangeNotifier asserts on notifyListeners, so this completes only behind the guard.
    await expectLater(refreshing, completes);
    expect(api.disconnects, 1);
  });

  test('an unavailable bridge explains itself instead of throwing', () async {
    final FakeEsp32Api api = FakeEsp32Api(availableValue: false);
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.available, isFalse);
    expect(controller.error, contains('desktop'));
  });

  test('without an injected bridge flutter test reports it unavailable', () {
    final Esp32Controller controller = Esp32Controller();

    expect(controller.available, isFalse);
    // dispose reaches the absent RustLib too, and must swallow that.
    expect(controller.dispose, returnsNormally);
  });

  test('connect without a port explains itself and opens nothing', () async {
    final FakeEsp32Api api = FakeEsp32Api();
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    await controller.connect();

    expect(controller.error, 'No serial port selected.');
    expect(api.connects, 0);
  });

  test('hello connects and exposes identity', () async {
    final FakeEsp32Api api = FakeEsp32Api();
    api.ports = <Esp32Device>[esp32Port('/dev/ttyACM0')];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.connect();
    expect(api.connects, 1);
    expect(api.connectedPath, '/dev/ttyACM0');
    expect(controller.connected, isFalse);

    api.events.add(
      esp32Event(
        'hello',
        firmware: '0.1.0',
        mac: 'E8:06:90:9D:3E:78',
        uptimeMs: 1234,
      ),
    );
    await _settle();

    expect(controller.connected, isTrue);
    expect(controller.firmware, '0.1.0');
    expect(controller.mac, 'E8:06:90:9D:3E:78');
    expect(controller.uptimeMs, 1234);
  });

  test('a port that cannot be opened is reported', () async {
    final FakeEsp32Api api = FakeEsp32Api()
      ..ports = <Esp32Device>[esp32Port('/dev/ttyACM0')]
      ..connectError = StateError('busy');
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await controller.refresh();

    await controller.connect();

    expect(controller.error, 'Could not open /dev/ttyACM0: Bad state: busy');
    expect(controller.connected, isFalse);
    expect(controller.loading, isFalse);
  });

  test('connecting again closes the open link first', () async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _connected();
    expect(controller.connected, isTrue);

    await controller.connect();

    expect(api.disconnects, 1);
    expect(api.connects, 2);
    expect(controller.connected, isFalse, reason: 'waits for the new hello');
  });

  test('a stream error drops the link and names the cause', () async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _connected();

    api.events.addError(StateError('port vanished'));
    await _settle();

    expect(controller.connected, isFalse);
    expect(controller.error, 'Connection failed: Bad state: port vanished');
  });

  test('the end of the event stream drops the link', () async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _connected();

    await api.events.close();
    await _settle();

    expect(controller.connected, isFalse);
    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
  });

  test('telemetry updates the board fields and the button', () async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _connected();

    api.events.add(
      esp32Event(
        'telemetry',
        uptimeMs: 5000,
        freeHeap: 4096,
        temperatureCentiC: 4210,
        flag: true,
        detectionCount: 3,
      ),
    );
    await _settle();

    expect(controller.uptimeMs, 5000);
    expect(controller.freeHeap, 4096);
    expect(controller.temperatureCentiC, 4210);
    expect(controller.buttonDown, isTrue);
    expect(controller.detectionCount, 3);

    api.events.add(esp32Event('telemetry'));
    await _settle();
    expect(controller.buttonDown, isFalse);
    expect(controller.detectionCount, 3, reason: 'a count is kept until sent');
  });

  test('pong and button events update their fields', () async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _connected();

    api.events
      ..add(esp32Event('pong', value: 7))
      ..add(esp32Event('button', flag: true));
    await _settle();
    expect(controller.lastPong, 7);
    expect(controller.buttonDown, isTrue);

    api.events.add(esp32Event('button'));
    await _settle();
    expect(controller.buttonDown, isFalse);
  });

  test('a camera event exposes on-device hits', () async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _connected();

    api.events.add(esp32Event('camera', value: 2, scorePermille: 934));
    await _settle();

    expect(controller.cameraSeen, isTrue);
    expect(controller.cameraDetections, 2);
    expect(controller.cameraScorePermille, 934);
  });

  test('LED and ping commands are only sent while connected', () async {
    final FakeEsp32Api api = FakeEsp32Api();
    api.ports = <Esp32Device>[esp32Port('/dev/ttyACM0')];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    controller.setLed(1, 2, 3);
    controller.ping();
    expect(api.leds, isEmpty);
    expect(api.pings, 0);

    await controller.refresh();
    await controller.connect();
    api.events.add(esp32Event('hello'));
    await _settle();

    controller.setLed(1, 2, 3, blinkMs: 500);
    controller.ping();
    expect(api.leds, <(int, int, int, int)>[(1, 2, 3, 500)]);
    expect(api.pings, 1);
  });

  test('a rejected LED or ping command is reported, not thrown', () async {
    final (FakeEsp32Api api, Esp32Controller controller) = await _connected();
    api.commandError = StateError('write timed out');

    controller.setLed(1, 2, 3);
    expect(controller.error, 'LED command failed: Bad state: write timed out');

    controller.ping();
    expect(controller.error, 'Ping failed: Bad state: write timed out');
    expect(controller.connected, isTrue);
  });

  test(
    'disconnect clears the link and a disconnect event surfaces the reason',
    () async {
      final (FakeEsp32Api api, Esp32Controller controller) = await _connected();

      api.events.add(esp32Event('disconnected', text: 'board unplugged'));
      await _settle();

      expect(controller.connected, isFalse);
      expect(controller.error, 'board unplugged');

      await controller.disconnect();
      expect(api.disconnects, 1);
    },
  );
}
