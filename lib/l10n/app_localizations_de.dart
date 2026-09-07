// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get homepage => 'Startseite';

  @override
  String get aboutme => 'Über mich';

  @override
  String get quotations => 'Zitate';

  @override
  String get books => 'Bücher';

  @override
  String get games => 'Spiele';

  @override
  String get gamesDescription =>
      'Bemerkenswerte Spiele und was es zu wissen gibt';

  @override
  String get booksDescription => 'Lesenswerte Bücher';

  @override
  String get films => 'Filme';

  @override
  String get filmsDescription => 'Sehenswerte Filme';

  @override
  String get data => 'Data';

  @override
  String get stream => 'Stream';

  @override
  String get quotationsDescription =>
      'Sammlung verschiedener Zitate, die mich inspirieren oder über die ich einfach lachen kann';

  @override
  String get aiPlayground => 'KI Spielwiese';

  @override
  String get renderingPlayground => 'Rendering Spielwiese';

  @override
  String get follow => 'Hier geht\'s weiter';

  @override
  String get rerunSqliteHealthcheck => 'SQLite Healthcheck erneut ausführen';

  @override
  String get sqliteError => 'SQLite Fehler';

  @override
  String get sqliteWebHint =>
      'Hinweis: Für Web muss eine sqlite3.wasm unter /web/sqlite3.wasm liegen.';
}
