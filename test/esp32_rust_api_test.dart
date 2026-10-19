// RustEsp32Api against a mocked core: each call must reach its generated binding with its arguments in the right slots.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/DevicePage/esp32_controller.dart';
import 'package:omni_accelerant/src/rust/api/esp32.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

import 'support/fake_esp32_api.dart';

/// The Rust core with one board plugged in, recording what the wrapper sends.
class _FakeRustApi extends Fake implements RustLibApi {
  bool available = true;
  final List<String> calls = <String>[];
  StreamController<Esp32Event> link = StreamController<Esp32Event>();

  @override
  bool crateApiEsp32Esp32Available() => available;

  @override
  Future<List<Esp32Device>> crateApiEsp32Esp32ListDevices() async =>
      <Esp32Device>[esp32Port('/dev/ttyACM0')];

  @override
  Stream<Esp32Event> crateApiEsp32Esp32Connect({required String path}) {
    calls.add('connect $path');
    link.add(esp32Event('hello', firmware: '0.2.0'));
    return link.stream;
  }

  @override
  Future<void> crateApiEsp32Esp32Disconnect() async => calls.add('disconnect');

  @override
  void crateApiEsp32Esp32SetLed({
    required int red,
    required int green,
    required int blue,
    required int blinkMs,
  }) => calls.add('led $red $green $blue $blinkMs');

  @override
  void crateApiEsp32Esp32Ping() => calls.add('ping');

  @override
  void crateApiEsp32Esp32SetTelemetryPeriod({required int ms}) =>
      calls.add('telemetry $ms');
}

void main() {
  final _FakeRustApi rust = _FakeRustApi();
  setUpAll(() => RustLib.initMock(api: rust));
  setUp(() {
    rust.calls.clear();
    rust.available = true;
    rust.link = StreamController<Esp32Event>();
  });

  test('every command reaches its binding with its own arguments', () async {
    const RustEsp32Api api = RustEsp32Api();

    expect(api.available, isTrue);
    rust.available = false;
    expect(api.available, isFalse);

    expect(await api.listDevices(), <Esp32Device>[esp32Port('/dev/ttyACM0')]);
    expect(
      await api.connect('/dev/ttyACM0').first,
      esp32Event('hello', firmware: '0.2.0'),
    );
    api.setLed(red: 1, green: 2, blue: 3, blinkMs: 400);
    api.ping();
    api.setTelemetryPeriod(250);
    await api.disconnect();

    expect(rust.calls, <String>[
      'connect /dev/ttyACM0',
      'led 1 2 3 400',
      'ping',
      'telemetry 250',
      'disconnect',
    ]);
  });

  test('a controller without an injected bridge drives the Rust one', () async {
    final Esp32Controller controller = Esp32Controller();
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.selectedPath, '/dev/ttyACM0');

    await controller.connect();
    await Future<void>.delayed(Duration.zero);
    expect(controller.connected, isTrue);
    expect(controller.firmware, '0.2.0');

    controller.setLed(0, 0, 255, blinkMs: 500);
    controller.ping();
    expect(rust.calls, <String>[
      'connect /dev/ttyACM0',
      'led 0 0 255 500',
      'ping',
    ]);
  });
}
