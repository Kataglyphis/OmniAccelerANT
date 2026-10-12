// The About page's SQLite line is the only place a broken sqlite3.wasm shows, so its error text and re-run need a test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AboutMePage/Widgets/sqlite3_healthcheck_widget.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, Future<String> Function() check) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Sqlite3HealthcheckWidget(check: check)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the result, and the button runs the check again', (
    WidgetTester tester,
  ) async {
    int runs = 0;
    await _pump(tester, () async => 'ok, run ${++runs}');
    expect(find.text('SQLite: ok, run 1'), findsOneWidget);

    await tester.tap(find.text('Re-run SQLite Healthcheck'));
    await tester.pumpAndSettle();
    expect(runs, 2);
    expect(find.text('SQLite: ok, run 2'), findsOneWidget);
  });

  testWidgets('a failed check names its error and adds the web hint', (
    WidgetTester tester,
  ) async {
    await _pump(tester, () async => throw StateError('no sqlite3.wasm'));
    expect(
      find.textContaining('SQLite Error: Bad state: no sqlite3.wasm'),
      findsOneWidget,
    );
    expect(
      find.textContaining('sqlite3.wasm must be served beside the page'),
      findsOneWidget,
    );
  });
}
