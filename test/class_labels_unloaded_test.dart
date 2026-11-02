import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/class_labels.dart';

void main() {
  test(
    'without the Rust core the names are absent and labels stay as given',
    () {
      expect(detectorClassNames(), isEmpty);
      expect(classLabel('cat', 'de'), 'cat');
      expect(watchedLabel(<String>['cat'], 'de'), 'Cat');
    },
  );
}
