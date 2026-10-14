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
      'Hinweis: Im Web muss sqlite3.wasm neben der Seite liegen (der Build kopiert web/sqlite3.wasm dorthin).';

  @override
  String get catInView => 'Katze im Bild';

  @override
  String catLastSeen(String when) {
    return 'Katze zuletzt gesehen: $when';
  }

  @override
  String get catNotSeenYet => 'Noch keine Katze gesehen';

  @override
  String get catLastArrival => 'Die letzte Ankunft der Katze';

  @override
  String get catArrivalVideo => 'Ankunft als Video ansehen';

  @override
  String get catEarlierVideos => 'Frühere Videos:';

  @override
  String get cameraSettingsNav => 'Kamera';

  @override
  String get cameraSettingsTitle => 'Kamera-Einstellungen';

  @override
  String get cameraNotReachable =>
      'Hier antwortet keine Cat Cam. Diese Einstellungen gibt es auf der Seite einer Cat Cam.';

  @override
  String get cameraRotation => 'Drehung';

  @override
  String get cameraSensitivity => 'Empfindlichkeit der Katzenerkennung';

  @override
  String get cameraSensitivityHelp =>
      'Höher heißt weniger Fehlalarme; niedriger erkennt eine Katze auch bei schlechtem Licht.';

  @override
  String get cameraName => 'Name';

  @override
  String get cameraSave => 'Speichern';

  @override
  String get cameraSaved => 'Gespeichert';

  @override
  String get cameraSaveFailed => 'Konnte nicht speichern';

  @override
  String get cameraInfo => 'Kamera-Info';

  @override
  String get cameraDevice => 'Kamera';

  @override
  String get cameraResolution => 'Auflösung';

  @override
  String get cameraFrameRate => 'Bildrate';

  @override
  String get cameraDetection => 'Katzenerkennung';

  @override
  String get cameraOn => 'an';

  @override
  String get cameraOff => 'aus';

  @override
  String get cameraModelRuns => 'Modellläufe';

  @override
  String get cameraVisits => 'Gezählte Besuche';

  @override
  String cameraLastScore(int percent) {
    return 'Letzte Erkennung: $percent %';
  }

  @override
  String catCamProblem(String problem) {
    return 'Die Kamera hat ein Problem: $problem';
  }

  @override
  String get cameraProblem => 'Problem';

  @override
  String get cameraNotACat => 'Das ist keine Katze';

  @override
  String get cameraNotACatHelp =>
      'Die markierte Stelle wird ab jetzt ignoriert, etwa ein Wäscheständer, den die Kamera für eine Katze hält.';

  @override
  String cameraIgnoredSpots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stellen werden ignoriert (grau in der Vorschau)',
      one: '1 Stelle wird ignoriert (grau in der Vorschau)',
    );
    return '$_temp0';
  }

  @override
  String get cameraWatchAgain => 'Wieder beachten';

  @override
  String catCamUnreachable(String time) {
    return 'Kamera nicht erreichbar seit $time';
  }

  @override
  String catAllVisits(int count) {
    return 'Alle $count Besuche';
  }

  @override
  String get catFewerVisits => 'Weniger Besuche';

  @override
  String get catOtherCameras => 'Andere Katzenkameras';

  @override
  String get catPeerUnreachable => 'Nicht erreichbar';

  @override
  String get cameraVersion => 'Version';

  @override
  String get cameraRecentDetections => 'Letzte Erkennungen';

  @override
  String get cameraRecentDetectionsHelp =>
      'War eine davon keine Katze? Markieren Sie sie, und die Kamera ignoriert diese Stelle ab jetzt.';

  @override
  String get cameraWasNotACat => 'Keine Katze';

  @override
  String get cameraSpotIgnored => 'Wird ignoriert';

  @override
  String cameraScoreValue(int percent) {
    return 'Eine Katze zählt ab $percent % Sicherheit';
  }

  @override
  String get catRotateLeft => 'Bild nach links drehen';

  @override
  String get catRotateRight => 'Bild nach rechts drehen';

  @override
  String catVideoFrom(String time) {
    return 'Video von $time';
  }

  @override
  String catRecentVisits(String visits) {
    return 'Letzte Besuche: $visits';
  }

  @override
  String catVisitStay(String time, String minutes) {
    return '$time ($minutes Min.)';
  }

  @override
  String get webrtcConnecting => 'Verbinde mit dem Signalisierungsserver';

  @override
  String get webrtcWaitingForCamera => 'Warte auf eine Kamera';

  @override
  String get webrtcNegotiating => 'Der Videostream wird ausgehandelt';

  @override
  String get webrtcStreaming => 'Wird übertragen';

  @override
  String get webrtcFailed => 'Der Stream konnte nicht gestartet werden';

  @override
  String webrtcSignallingLost(int ms) {
    return 'Verbindung zum Signalisierungsserver verloren – neuer Versuch alle $ms ms.';
  }

  @override
  String get webrtcCameraGone => 'Die Kamera ist offline gegangen.';

  @override
  String webrtcNoSession(String camera) {
    return 'Konnte keine Sitzung für die Kamera $camera öffnen.';
  }

  @override
  String get webrtcPeerError =>
      'Die Verbindung meldete einen Fehler. Ist die Kamera ein anderes Gerät, prüfen Sie, ob der WebRTC-UDP-Bereich es erreicht.';

  @override
  String get webrtcPeerNotStarted =>
      'Die Verbindung konnte nicht gestartet werden.';

  @override
  String get webrtcNoCamera =>
      'Der Signalisierungsserver läuft, aber keine Kamera hat sich gemeldet. Starten Sie kataglyphis_cat_webrtc auf dem Kamerarechner.';

  @override
  String get webrtcExchangingCandidates =>
      'ICE-Kandidaten werden ausgetauscht.';

  @override
  String get webrtcSeeConsole =>
      'Den zugrunde liegenden Fehler zeigt die Browser-Konsole.';
}
