import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/app_pages.dart';
import 'package:omni_accelerant/src/boot/url_options.dart';

void main() {
  test('?lang= names the starting language, any case', () {
    expect(
      localeFromUrl(
        Uri.parse('https://example.org/app/?lang=en#/aiPlayground'),
      ),
      const Locale('en'),
    );
    expect(
      localeFromUrl(Uri.parse('https://example.org/app/?lang=DE')),
      const Locale('de'),
    );
  });

  test(
    'no, an empty or a malformed lang leaves the app its first language',
    () {
      for (final String url in <String>[
        'https://example.org/app/',
        'https://example.org/app/?lang=',
        'https://example.org/app/?lang=en-US',
        'https://example.org/app/?lang=e',
        'file:///home/user/',
      ]) {
        expect(localeFromUrl(Uri.parse(url)), isNull, reason: url);
      }
    },
  );

  test(
    'the web passes the browser\'s languages in order, a native app none',
    () {
      const List<Locale> browser = <Locale>[Locale('de', 'DE'), Locale('en')];
      expect(browserLocales(isWeb: true, platformLocales: browser), browser);
      expect(browserLocales(isWeb: false, platformLocales: browser), isEmpty);
    },
  );

  test(
    'a start route picks its rail page, anything else keeps the fallback',
    () {
      final int playground = appPages.indexWhere(
        (page) => page.route == '/aiPlayground',
      );
      expect(playground, greaterThan(0));
      expect(startPageIndex('/aiPlayground', 0), playground);
      expect(startPageIndex('', 0), 0);
      expect(startPageIndex('/noSuchPage', 2), 2);
    },
  );

  test(
    'a plain build names no start route, so the camera page stays first',
    () {
      expect(hostedStartRoute, isEmpty);
    },
  );
}
