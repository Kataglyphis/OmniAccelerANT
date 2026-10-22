@TestOn('vm')
library;

import 'package:anthology_test_support/app_contracts.dart';
import 'package:flutter_test/flutter_test.dart' show TestOn;
import 'package:omni_accelerant/main.dart';

void main() {
  registerAppLayoutTests(
    app: () => const App(),
    routes: const <String>[
      '/stream',
      '/cameraSettings',
      '/device',
      '/landingPage',
      '/aboutMe',
      '/privacyPolicy',
      '/aiBlog',
    ],
  );
  registerAppNavigationContract(
    app: () => const App(),
    navigationIndex: 1,
    route: '/cameraSettings',
  );
}
