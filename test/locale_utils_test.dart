import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/utils/locale_utils.dart';

/// What [localizedValue] picks under [locale].
Future<String> _pick(WidgetTester tester, Locale locale) async {
  late String picked;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const <LocalizationsDelegate<dynamic>>[
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Builder(
        builder: (BuildContext context) {
          picked = localizedValue(context, de: 'Katze', en: 'cat');
          return const SizedBox();
        },
      ),
    ),
  );
  return picked;
}

void main() {
  testWidgets('German picks the German value, English the English one', (
    WidgetTester tester,
  ) async {
    expect(await _pick(tester, const Locale('de')), 'Katze');
    expect(await _pick(tester, const Locale('en')), 'cat');
  });

  testWidgets('a German locale with a country is German too', (
    WidgetTester tester,
  ) async {
    expect(await _pick(tester, const Locale('de', 'AT')), 'Katze');
    expect(await _pick(tester, const Locale('de', 'CH')), 'Katze');
    expect(await _pick(tester, const Locale('fr')), 'cat');
  });
}
