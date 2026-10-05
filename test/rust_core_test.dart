// The web boots without the Rust core (Firefox/Safari refuse its shared memory over plain HTTP); native must not.

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_accelerant/src/boot/rust_core.dart';

void main() {
  group('loadRustCore', () {
    test('records a core that loaded', () async {
      expect(await loadRustCore(() async {}, optional: false), isTrue);
      expect(rustCoreAvailable, isTrue);
    });

    test('an optional core that fails is skipped, not fatal', () async {
      final bool loaded = await loadRustCore(
        () async => throw StateError('shared memory refused'),
        optional: true,
      );
      expect(loaded, isFalse);
      expect(rustCoreAvailable, isFalse);
    });

    test('a required core that fails still stops the boot', () async {
      await expectLater(
        loadRustCore(() async => throw StateError('no wasm'), optional: false),
        throwsStateError,
      );
      expect(rustCoreAvailable, isFalse);
    });
  });
}
