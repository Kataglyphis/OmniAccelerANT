@TestOn('vm')
library;

import 'package:anthology_test_support/app_contracts.dart';
import 'package:flutter_test/flutter_test.dart' show TestOn;
import 'package:omni_accelerant/app_pages.dart';
import 'package:omni_accelerant/main.dart';

void main() {
  registerAppLayoutTests(
    app: () => const App(),
    routes: <String>[
      for (final page in appPages) page.route,
      '/privacyPolicy',
      '/aiBlog',
    ],
  );
  registerAppNavigationContract(
    app: () => const App(),
    navigationIndex: 1,
    route: appPages[1].route,
  );
}
