import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:omni_accelerant/src/rust/api/esp32.dart';

/// The bridge surface the controller needs, so tests can fake it without Rust.
abstract class Esp32Api {
  bool get available;

  Future<List<Esp32Device>> listDevices();

  Stream<Esp32Event> connect(String path);

  Future<void> disconnect();

  void setLed({
    required int red,
    required int green,
    required int blue,
    required int blinkMs,
  });

  void ping();

  void setTelemetryPeriod(int ms);
}

/// The real bridge. `RustLib` is absent in `flutter test`, which is why the page talks
/// to [Esp32Api] instead of these top-level functions.
class RustEsp32Api implements Esp32Api {
  const RustEsp32Api();

  @override
  bool get available => esp32Available();

  @override
  Future<List<Esp32Device>> listDevices() => esp32ListDevices();

  @override
  Stream<Esp32Event> connect(String path) => esp32Connect(path: path);

  @override
  Future<void> disconnect() => esp32Disconnect();

  @override
  void setLed({
    required int red,
    required int green,
    required int blue,
    required int blinkMs,
  }) {
    esp32SetLed(red: red, green: green, blue: blue, blinkMs: blinkMs);
  }

  @override
  void ping() => esp32Ping();

  @override
  void setTelemetryPeriod(int ms) => esp32SetTelemetryPeriod(ms: ms);
}

/// Owns the port choice and the event stream; the page only renders it.
class Esp32Controller extends ChangeNotifier {
  Esp32Controller({Esp32Api? api}) : _api = api ?? const RustEsp32Api();

  final Esp32Api _api;

  List<Esp32Device> devices = const <Esp32Device>[];
  String? selectedPath;
  bool loading = false;
  bool connected = false;
  String? error;

  String? firmware;
  String? mac;
  int? uptimeMs;
  int? freeHeap;
  int? temperatureCentiC;
  bool buttonDown = false;
  int detectionCount = 0;
  bool cameraSeen = false;
  int cameraDetections = 0;
  int cameraScorePermille = 0;
  int lastPong = 0;

  StreamSubscription<Esp32Event>? _subscription;
  bool _disposed = false;

  bool get available {
    try {
      return _api.available;
    } catch (_) {
      // flutter test: the generated bridge has no RustLib.
      return false;
    }
  }

  Future<void> refresh() async {
    if (!available) {
      error = 'The ESP32 bridge is available in desktop builds only.';
      _notify();
      return;
    }

    loading = true;
    error = null;
    _notify();
    try {
      final List<Esp32Device> found = await _api.listDevices();
      devices = found;
      if (found.isEmpty) {
        selectedPath = null;
      } else if (!found.any((Esp32Device d) => d.path == selectedPath)) {
        // Prefer the board over an unrelated adapter when both are plugged in.
        selectedPath = found
            .firstWhere(
              (Esp32Device d) => d.espressif,
              orElse: () => found.first,
            )
            .path;
      }
    } catch (e) {
      error = 'Could not list serial ports: $e';
    } finally {
      loading = false;
      _notify();
    }
  }

  void select(String? path) {
    selectedPath = path;
    _notify();
  }

  Future<void> connect() async {
    final String? path = selectedPath;
    if (path == null) {
      error = 'No serial port selected.';
      _notify();
      return;
    }

    if (_subscription != null) {
      await disconnect();
    }
    loading = true;
    error = null;
    _notify();
    try {
      final Stream<Esp32Event> events = _api.connect(path);
      _subscription = events.listen(
        _onEvent,
        onError: (Object e) {
          error = 'Connection failed: $e';
          connected = false;
          loading = false;
          _notify();
        },
        onDone: () {
          connected = false;
          loading = false;
          _notify();
        },
      );
    } catch (e) {
      error = 'Could not open $path: $e';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _api.disconnect();
    } catch (_) {
      // Already gone; the UI state below is what matters.
    }
    connected = false;
    _notify();
  }

  void setLed(int red, int green, int blue, {int blinkMs = 0}) {
    if (!connected) return;
    try {
      _api.setLed(red: red, green: green, blue: blue, blinkMs: blinkMs);
    } catch (e) {
      error = 'LED command failed: $e';
      _notify();
    }
  }

  void ping() {
    if (!connected) return;
    try {
      _api.ping();
    } catch (e) {
      error = 'Ping failed: $e';
      _notify();
    }
  }

  void _onEvent(Esp32Event event) {
    switch (event.kind) {
      case 'hello':
        connected = true;
        error = null;
        firmware = event.firmware;
        mac = event.mac;
        uptimeMs = event.uptimeMs;
        break;
      case 'telemetry':
        uptimeMs = event.uptimeMs;
        freeHeap = event.freeHeap;
        temperatureCentiC = event.temperatureCentiC;
        buttonDown = event.flag ?? false;
        detectionCount = event.detectionCount ?? detectionCount;
        break;
      case 'pong':
        lastPong = event.value ?? 0;
        break;
      case 'camera':
        cameraSeen = true;
        cameraDetections = event.value ?? 0;
        cameraScorePermille = event.scorePermille ?? 0;
        break;
      case 'button':
        buttonDown = event.flag ?? false;
        break;
      case 'disconnected':
        connected = false;
        error = event.text;
        break;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final StreamSubscription<Esp32Event>? subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    try {
      unawaited(_api.disconnect());
    } catch (_) {
      // flutter test: the generated bridge has no RustLib.
    }
    super.dispose();
  }
}
