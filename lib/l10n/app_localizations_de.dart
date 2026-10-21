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
  String detectionInView(String what) {
    return '$what im Bild';
  }

  @override
  String detectionLastSeen(String when) {
    return 'Zuletzt gesehen: $when';
  }

  @override
  String get detectionNotSeenYet => 'Noch nichts gesehen';

  @override
  String get detectionLastArrival => 'Die letzte Ankunft';

  @override
  String get detectionArrivalVideo => 'Ankunft als Video ansehen';

  @override
  String get detectionEarlierVideos => 'Frühere Videos:';

  @override
  String get cameraSettingsNav => 'Kamera';

  @override
  String get deviceNav => 'Gerät';

  @override
  String get cameraSettingsTitle => 'Kamera-Einstellungen';

  @override
  String get cameraNotReachable =>
      'Hier antwortet keine ObservANT-Kamera. Diese Einstellungen gibt es auf der Seite einer ObservANT-Kamera.';

  @override
  String get cameraRotation => 'Drehung';

  @override
  String get cameraSensitivity => 'Empfindlichkeit der Erkennung';

  @override
  String get cameraSensitivityHelp =>
      'Höher heißt weniger Fehlalarme; niedriger erkennt auch bei schlechtem Licht.';

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
  String get cameraDetection => 'Erkennung';

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
  String observantProblem(String problem) {
    return 'Die Kamera hat ein Problem: $problem';
  }

  @override
  String get cameraProblem => 'Problem';

  @override
  String get cameraFalseAlarm => 'Fehlalarm';

  @override
  String get cameraFalseAlarmHelp =>
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
  String observantUnreachable(String time) {
    return 'Kamera nicht erreichbar seit $time';
  }

  @override
  String detectionAllVisits(int count) {
    return 'Alle $count Besuche';
  }

  @override
  String get detectionFewerVisits => 'Weniger Besuche';

  @override
  String get observantOthers => 'Andere Kameras';

  @override
  String get observantPeerUnreachable => 'Nicht erreichbar';

  @override
  String get cameraVersion => 'Version';

  @override
  String get cameraPrivacy => 'Privatsphäre-Filter';

  @override
  String get cameraPrivacyPixelate =>
      'verpixelt alles außer den erkannten Tieren (in der Einstellungsdatei gesetzt)';

  @override
  String get cameraPrivacyOff => 'aus (in der Einstellungsdatei gesetzt)';

  @override
  String get cameraClasses => 'Was erkannt wird';

  @override
  String get cameraAddClass => 'Klasse hinzufügen';

  @override
  String get cameraClassesHelp =>
      'Besuche, Benachrichtigungen und Rahmen zählen diese Objekte (COCO-Klassen; Katze ist der Standard). Eine Änderung gilt ab dem nächsten Modelllauf. Der Privatsphäre-Filter lässt jedes davon scharf, auch Personen.';

  @override
  String get cameraClassesLocked =>
      'Der Privatsphäre-Filter ist an, darum lässt sich das nur in der Einstellungsdatei (observant.toml) ändern.';

  @override
  String get cameraRetry => 'Erneut versuchen';

  @override
  String get detectionTooDark =>
      'Zu dunkel: die Kamera sieht schwarz und erkennt nichts';

  @override
  String get devStats => 'Statistik';

  @override
  String get devStatsNone =>
      'Noch keine Zahlen: die Kamera meldet keine, und der Browser spielt nichts ab.';

  @override
  String get devStatsCamera => 'Kamera';

  @override
  String devStatsCameraValue(String fps, String configured) {
    return '$fps von $configured fps';
  }

  @override
  String get devStatsModel => 'Erkennung';

  @override
  String devStatsModelValue(String ms, String rate) {
    return '$ms ms pro Lauf, $rate Läufe/s';
  }

  @override
  String get devStatsCpu => 'CPU';

  @override
  String devStatsCpuValue(String percent, String cores, String load) {
    return '$percent % eines Kerns, $cores Kerne, Last $load';
  }

  @override
  String get devStatsMemory => 'Arbeitsspeicher';

  @override
  String get devStatsTemperature => 'Temperatur';

  @override
  String get devStatsUptime => 'Läuft seit';

  @override
  String devStatsUptimeValue(String hours, String minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get devStatsViewers => 'Zuschauer';

  @override
  String get devStatsBrowser => 'Dieser Browser';

  @override
  String devStatsBrowserValue(String fps, String size, String dropped) {
    return '$fps fps, $size, $dropped verworfen';
  }

  @override
  String get observantPixelated =>
      'Privatsphäre-Filter an: alles außer den erkannten Tieren ist verpixelt';

  @override
  String get cameraRecentDetections => 'Letzte Erkennungen';

  @override
  String get cameraRecentDetectionsHelp =>
      'War eine davon ein Fehlalarm? Markieren Sie sie, und die Kamera ignoriert diese Stelle ab jetzt.';

  @override
  String get cameraWasFalseAlarm => 'Fehlalarm';

  @override
  String get cameraSpotIgnored => 'Wird ignoriert';

  @override
  String cameraScoreValue(int percent) {
    return 'Eine Erkennung zählt ab $percent % Sicherheit';
  }

  @override
  String get cameraRotateLeft => 'Bild nach links drehen';

  @override
  String get cameraRotateRight => 'Bild nach rechts drehen';

  @override
  String detectionVideoFrom(String time) {
    return 'Video von $time';
  }

  @override
  String detectionRecentVisits(String visits) {
    return 'Letzte Besuche: $visits';
  }

  @override
  String detectionVisitStay(String time, String minutes) {
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
      'Der Signalisierungsserver läuft, aber keine Kamera hat sich gemeldet. Starten Sie kataglyphis_observant auf dem Kamerarechner.';

  @override
  String get webrtcExchangingCandidates =>
      'ICE-Kandidaten werden ausgetauscht.';

  @override
  String get webrtcSeeConsole =>
      'Den zugrunde liegenden Fehler zeigt die Browser-Konsole.';

  @override
  String get visitStats => 'Besuche';

  @override
  String visitStatsNone(int days) {
    return 'Keine Besuche in den letzten $days Tagen.';
  }

  @override
  String visitStatsSummary(int today, int total, int days) {
    return '$today heute, $total in $days Tagen';
  }

  @override
  String visitStatsAverageStay(String minutes) {
    return 'Im Schnitt $minutes min geblieben';
  }

  @override
  String get visitStatsPerDay => 'Pro Tag';

  @override
  String get visitStatsPerHour => 'Nach Uhrzeit';
}
