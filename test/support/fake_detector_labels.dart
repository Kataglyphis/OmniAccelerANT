import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

/// Eighty class names with the ones the tests use at their real ids; the rest are placeholders.
final List<String> fakeDetectorLabels = List<String>.generate(
  80,
  (id) => switch (id) {
    0 => 'person',
    15 => 'cat',
    16 => 'dog',
    _ => 'class $id',
  },
);

/// The Rust core's class-name API without Rust.
class FakeDetectorLabelsApi extends Fake implements RustLibApi {
  @override
  List<String> crateApiOnnxDetectorLabels() => fakeDetectorLabels;
}
