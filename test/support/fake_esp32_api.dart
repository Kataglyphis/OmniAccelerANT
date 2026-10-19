import 'dart:async';

import 'package:omni_accelerant/Pages/DevicePage/esp32_controller.dart';
import 'package:omni_accelerant/src/rust/api/esp32.dart';

/// The bridge without Rust or a board: tests push [events] and read back the commands.
class FakeEsp32Api implements Esp32Api {
  FakeEsp32Api({this.availableValue = true});

  bool availableValue;
  List<Esp32Device> ports = const <Esp32Device>[];
  final StreamController<Esp32Event> events =
      StreamController<Esp32Event>.broadcast();

  /// When set, [listDevices] waits for it, so a test can watch the loading state.
  Completer<List<Esp32Device>>? pendingList;
  Object? listError;
  Object? connectError;
  Object? commandError;

  int connects = 0;
  String? connectedPath;
  int disconnects = 0;
  int pings = 0;
  final List<(int, int, int, int)> leds = <(int, int, int, int)>[];
  final List<int> telemetryPeriods = <int>[];

  @override
  bool get available => availableValue;

  @override
  Future<List<Esp32Device>> listDevices() async {
    final Object? failure = listError;
    if (failure != null) throw failure;
    final Completer<List<Esp32Device>>? pending = pendingList;
    if (pending != null) return pending.future;
    return ports;
  }

  @override
  Stream<Esp32Event> connect(String path) {
    connects++;
    final Object? failure = connectError;
    if (failure != null) throw failure;
    connectedPath = path;
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
    final Object? failure = commandError;
    if (failure != null) throw failure;
    leds.add((red, green, blue, blinkMs));
  }

  @override
  void ping() {
    final Object? failure = commandError;
    if (failure != null) throw failure;
    pings++;
  }

  @override
  void setTelemetryPeriod(int ms) => telemetryPeriods.add(ms);
}

Esp32Device esp32Port(String path, {bool espressif = true}) {
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

Esp32Event esp32Event(
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
