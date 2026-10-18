import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/DevicePage/esp32_controller.dart';
import 'package:omni_accelerant/src/rust/api/esp32.dart';

class _FakeEsp32Api implements Esp32Api {
  _FakeEsp32Api({this.availableValue = true});

  bool availableValue;
  List<Esp32Device> ports = const <Esp32Device>[];
  final StreamController<Esp32Event> events =
      StreamController<Esp32Event>.broadcast();

  int connects = 0;
  int disconnects = 0;
  int pings = 0;
  final List<(int, int, int, int)> leds = <(int, int, int, int)>[];

  @override
  bool get available => availableValue;

  @override
  Future<List<Esp32Device>> listDevices() async => ports;

  @override
  Stream<Esp32Event> connect(String path) {
    connects++;
    return events.stream;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  void setLed({
    required int red,
    required int green,
    required int blue,
    required int blinkMs,
  }) {
    leds.add((red, green, blue, blinkMs));
  }

  @override
  void ping() {
    pings++;
  }

  @override
  void setTelemetryPeriod(int ms) {}
}

Esp32Device _port(String path, {bool espressif = true}) {
  return Esp32Device(
    path: path,
    serialNumber: espressif ? 'E8:06:90:9D:3E:78' : null,
    product: espressif ? 'USB JTAG/serial debug unit' : 'FT232R USB UART',
    manufacturer: espressif ? 'Espressif' : 'FTDI',
    vendorId: espressif ? 0x303A : 0x0403,
    productId: espressif ? 0x1001 : 0x6001,
    espressif: espressif,
  );
}

Esp32Event _event(
  String kind, {
  String? text,
  int? value,
  bool? flag,
  String? firmware,
  String? mac,
  int? uptimeMs,
  int? freeHeap,
  int? temperatureCentiC,
  int? detectionCount,
  int? scorePermille,
}) {
  return Esp32Event(
    kind: kind,
    text: text,
    value: value,
    flag: flag,
    firmware: firmware,
    mac: mac,
    uptimeMs: uptimeMs,
    freeHeap: freeHeap,
    temperatureCentiC: temperatureCentiC,
    detectionCount: detectionCount,
    scorePermille: scorePermille,
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('refresh selects the first port and preselects it', () async {
    final _FakeEsp32Api api = _FakeEsp32Api();
    api.ports = <Esp32Device>[
      _port('/dev/ttyUSB0', espressif: false),
      _port('/dev/ttyACM0'),
    ];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.devices, hasLength(2));
    expect(controller.selectedPath, '/dev/ttyACM0');
    expect(controller.error, isNull);
  });

  test('an unavailable bridge explains itself instead of throwing', () async {
    final _FakeEsp32Api api = _FakeEsp32Api(availableValue: false);
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.available, isFalse);
    expect(controller.error, contains('desktop'));
  });

  test('hello connects and exposes identity', () async {
    final _FakeEsp32Api api = _FakeEsp32Api();
    api.ports = <Esp32Device>[_port('/dev/ttyACM0')];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.connect();
    expect(api.connects, 1);
    expect(controller.connected, isFalse);

    api.events.add(
      _event(
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

  test('telemetry updates the board fields and the button', () async {
    final _FakeEsp32Api api = _FakeEsp32Api();
    api.ports = <Esp32Device>[_port('/dev/ttyACM0')];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.connect();

    api.events.add(
      _event(
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
  });

  test('a camera event exposes on-device hits', () async {
    final _FakeEsp32Api api = _FakeEsp32Api();
    api.ports = <Esp32Device>[_port('/dev/ttyACM0')];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.connect();

    api.events.add(_event('camera', value: 2, scorePermille: 934));
    await _settle();

    expect(controller.cameraSeen, isTrue);
    expect(controller.cameraDetections, 2);
    expect(controller.cameraScorePermille, 934);
  });

  test('LED and ping commands are only sent while connected', () async {
    final _FakeEsp32Api api = _FakeEsp32Api();
    api.ports = <Esp32Device>[_port('/dev/ttyACM0')];
    final Esp32Controller controller = Esp32Controller(api: api);
    addTearDown(controller.dispose);

    controller.setLed(1, 2, 3);
    controller.ping();
    expect(api.leds, isEmpty);
    expect(api.pings, 0);

    await controller.refresh();
    await controller.connect();
    api.events.add(_event('hello'));
    await _settle();

    controller.setLed(1, 2, 3, blinkMs: 500);
    controller.ping();
    expect(api.leds, <(int, int, int, int)>[(1, 2, 3, 500)]);
    expect(api.pings, 1);
  });

  test(
    'disconnect clears the link and a disconnect event surfaces the reason',
    () async {
      final _FakeEsp32Api api = _FakeEsp32Api();
      api.ports = <Esp32Device>[_port('/dev/ttyACM0')];
      final Esp32Controller controller = Esp32Controller(api: api);
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.connect();
      api.events.add(_event('hello'));
      await _settle();

      api.events.add(_event('disconnected', text: 'board unplugged'));
      await _settle();

      expect(controller.connected, isFalse);
      expect(controller.error, 'board unplugged');

      await controller.disconnect();
      expect(api.disconnects, 1);
    },
  );
}
