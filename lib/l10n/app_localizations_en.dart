// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get homepage => 'Homepage';

  @override
  String get aboutme => 'About me';

  @override
  String get quotations => 'Quotations';

  @override
  String get books => 'Books';

  @override
  String get games => 'Games';

  @override
  String get gamesDescription => 'Funny Games and what there is to know about';

  @override
  String get booksDescription => 'Books worth reading';

  @override
  String get films => 'Films';

  @override
  String get filmsDescription => 'Films worth watching';

  @override
  String get data => 'Data';

  @override
  String get stream => 'Stream';

  @override
  String get quotationsDescription =>
      'Collection of various quotations I am inspired by or just can laugh about';

  @override
  String get aiPlayground => 'AI Playground';

  @override
  String get renderingPlayground => 'Rendering Playground';

  @override
  String get follow => 'Visit page';

  @override
  String get rerunSqliteHealthcheck => 'Re-run SQLite Healthcheck';

  @override
  String get sqliteError => 'SQLite Error';

  @override
  String get sqliteWebHint =>
      'Note: For web, sqlite3.wasm must be located at /web/sqlite3.wasm.';
}
