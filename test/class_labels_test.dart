import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/class_labels.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

import 'support/fake_detector_labels.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: FakeDetectorLabelsApi()));

  test('the class names are the core detector_labels, at their ids', () {
    expect(detectorClassNames(), fakeDetectorLabels);
  });

  test('German names follow the class id, for every id the core reports', () {
    expect(classLabel('cat', 'de'), 'Katze');
    expect(classLabel('dog', 'de'), 'Hund');
    expect(classLabel(fakeDetectorLabels[79], 'de'), 'Zahnbürste');
    expect(classLabel('cat', 'en'), 'cat');
    expect(classLabel('unicorn', 'de'), 'unicorn');
    expect(watchedLabel(<String>['cat', 'dog'], 'de'), 'Katze / Hund');
  });
}
