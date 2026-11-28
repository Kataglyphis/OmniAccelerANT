// ignore_for_file: deprecated_member_use

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
  String get webLicensesIntro =>
      'Alles, was diese Web-App ausliefert, aus ihrem eigenen Build gelesen: jede Komponente, ihre Lizenz und die Dateien, die sie abdeckt.';

  @override
  String webLicensesSummary(int files, int components) {
    return '$files Dateien in $components Komponenten';
  }

  @override
  String get webLicensesMissing =>
      'Dieser Build enthält kein Lizenzverzeichnis seiner Web-Dateien.';

  @override
  String get webLicensesTextFailed =>
      'Der Lizenztext konnte nicht geladen werden.';

  @override
  String webLicensesFiles(int count) {
    return 'Ausgelieferte Dateien ($count)';
  }

  @override
  String webLicensesIncludes(String names) {
    return 'Enthaltene Hinweise: $names';
  }

  @override
  String webLicensesSource(String url) {
    return 'Quelle: $url';
  }

  @override
  String get webLicensesGroupApp => 'Diese App';

  @override
  String get webLicensesGroupEngine => 'Flutter-Web-Engine';

  @override
  String get webLicensesGroupDart => 'Dart-Pakete';

  @override
  String get webLicensesGroupWasm => 'WebAssembly-Module';

  @override
  String get webLicensesGroupCargo => 'Rust-Crates in den WebAssembly-Modulen';

  @override
  String get webLicensesGroupOrt => 'ONNX Runtime Web';

  @override
  String get webLicensesGroupModels => 'KI-Modelle';

  @override
  String get webLicensesGroupFonts => 'Schriften';

  @override
  String get webLicensesGroupJavascript => 'JavaScript-Bibliotheken';

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
    return 'Verbindung zum Signalisierungsserver verloren – neuer Versuch in $ms ms.';
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

  @override
  String get aiPlaygroundNav => 'KI';

  @override
  String get aiPlaygroundTitle => 'KI-Spielwiese';

  @override
  String get aiSettings => 'Modell und Einstellungen';

  @override
  String get aiSourceEndpoint => 'Endpunkt';

  @override
  String get aiSourceLocal => 'Lokales Modell';

  @override
  String get aiLocalUnavailable =>
      'Dieser Build führt kein lokales Modell aus; die Linux- und Windows-Builds tun es über das ONNX Runtime GenAI der Chain.';

  @override
  String get aiModelDir => 'GenAI-Modellverzeichnis';

  @override
  String get aiProvider => 'Ausführungsanbieter';

  @override
  String get aiBaseUrl => 'Basis-URL (ohne /v1)';

  @override
  String get aiModel => 'Modell';

  @override
  String get aiApiKey => 'API-Schlüssel';

  @override
  String get aiSystemPrompt => 'Systemprompt';

  @override
  String get aiMaxTokens => 'Höchstens neue Tokens';

  @override
  String get aiTemperature => 'Temperatur';

  @override
  String get aiSeed => 'Seed (leer: jedes Mal eine neue Antwort)';

  @override
  String get aiJsonSchema => 'JSON-Schema der Antwort (leer: freier Text)';

  @override
  String get aiStop => 'Stoppzeichenfolgen, eine pro Zeile';

  @override
  String get aiClear => 'Neues Gespräch';

  @override
  String aiError(String detail) {
    return 'Das Modell ist fehlgeschlagen: $detail';
  }

  @override
  String aiErrorModelLoad(String detail) {
    return 'Das Modell ließ sich nicht laden; bitte den Modellordner prüfen. ($detail)';
  }

  @override
  String aiErrorLibrary(String detail) {
    return 'Diese Version kann kein Modell selbst ausführen; bitte einen Server nutzen. ($detail)';
  }

  @override
  String aiErrorProvider(String detail) {
    return 'Das gewählte Gerät gibt es hier nicht; bitte CPU wählen. ($detail)';
  }

  @override
  String aiErrorEndpoint(String detail) {
    return 'Der Server hat nicht richtig geantwortet; bitte Adresse und Betrieb prüfen. ($detail)';
  }

  @override
  String aiErrorTimedOut(String detail) {
    return 'Der Server hat zu lange für die Antwort gebraucht; bitte erneut oder kürzer fragen. ($detail)';
  }

  @override
  String aiErrorTokenizer(String detail) {
    return 'Der Tokenizer des Modells ist fehlgeschlagen; der Modellordner ist vielleicht unvollständig. ($detail)';
  }

  @override
  String aiErrorChatTemplate(String detail) {
    return 'Die Chat-Vorlage des Modells ließ sich nicht anwenden; vielleicht ist es kein Chat-Modell. ($detail)';
  }

  @override
  String aiErrorEncode(String detail) {
    return 'Die Frage ließ sich nicht für das Modell kodieren. ($detail)';
  }

  @override
  String aiErrorGeneration(String detail) {
    return 'Das Modell ist beim Antworten mit einem Fehler abgebrochen. ($detail)';
  }

  @override
  String aiErrorStreamLine(String detail) {
    return 'Der Server hat einen zu großen Teil seiner Antwort geschickt. ($detail)';
  }

  @override
  String aiErrorJsonSchema(String detail) {
    return 'Diese Modellversion kann kein JSON-Schema einhalten; bitte das Schema leer lassen. ($detail)';
  }

  @override
  String aiErrorEmbeddings(String detail) {
    return 'Dieses Modell kann keine Embeddings erzeugen. ($detail)';
  }

  @override
  String aiErrorInvalid(String detail) {
    return 'Die Anfrage wurde abgelehnt; bitte die Einstellungen prüfen. ($detail)';
  }

  @override
  String aiErrorContextLength(String detail) {
    return 'Das Gespräch ist zu lang für das Modell; bitte leeren oder weniger neue Tokens erlauben. ($detail)';
  }

  @override
  String aiErrorNoAnswer(String detail) {
    return 'Das Modell hat keine Antwort gegeben; bitte erneut oder anders fragen. ($detail)';
  }

  @override
  String get visitQuestions => 'Fragen zu den Besuchen';

  @override
  String get visitQuestionsSummarise => 'Heute zusammenfassen';

  @override
  String get visitQuestionsHint =>
      'Die Antworten stammen aus den Besuchszahlen. Ein Sprachmodell kann sich irren, und es sieht das Bild nicht.';

  @override
  String get visitQuestionsFacts => 'Was das Modell erfahren hat';

  @override
  String get visitQuestionsNoVisits => 'Heute keine Besuche.';

  @override
  String get visitQuestionsUnreachable => 'Die Kamera hat nicht geantwortet.';

  @override
  String visitQuestionsFailed(String reason) {
    return 'Die Kamera konnte nicht antworten: $reason';
  }

  @override
  String get observantAddressTitle => 'ObservANT-Adresse';

  @override
  String get observantAddressHelp =>
      'Leer: das ObservANT, das diese Seite ausliefert. Eine andere Kamera: ihre Adresse, etwa http://catcam.local:8080.';

  @override
  String get observantAddressLabel => 'Adresse';

  @override
  String get observantAddressConnect => 'Verbinden';

  @override
  String get observantAddressClear => 'Leeren';

  @override
  String get observantAddressCheckAgain => 'Erneut prüfen';

  @override
  String get observantAddressOpenOwn => 'Eigene Seite der Kamera öffnen';

  @override
  String get observantAddressOwn =>
      'Keine Adresse gesetzt: Diese Seite liest das ObservANT, das sie ausliefert.';

  @override
  String observantAddressChecking(String address) {
    return 'Frage $address …';
  }

  @override
  String observantAddressPrompting(String address) {
    return 'Chrome fragt, ob diese Website Geräte in Ihrem lokalen Netzwerk erreichen darf. Wählen Sie Zulassen, um $address zu lesen.';
  }

  @override
  String observantAddressConnected(
    String name,
    String version,
    String address,
  ) {
    return 'Verbunden mit $name (ObservANT $version) unter $address.';
  }

  @override
  String get observantAddressRemoteLimits =>
      'Einer anderen Seite gibt ObservANT Status, Besuche und Bilder. Livebild, Einstellungen und Fragen gehen auf der eigenen Seite der Kamera: ObservANT nimmt sie nur von dort an.';

  @override
  String get observantAddressNotUrl => 'Das ist keine Adresse.';

  @override
  String get observantAddressScheme =>
      'Beginnen Sie mit http:// oder https://.';

  @override
  String get observantAddressNoHost =>
      'Die Adresse braucht einen Host, etwa catcam.local.';

  @override
  String get observantAddressCredentials =>
      'Lassen Sie Benutzer und Passwort weg.';

  @override
  String get observantAddressPath =>
      'Nur die Adresse der Kamera: kein Pfad, keine Abfrage, kein #.';

  @override
  String get observantAddressPort =>
      'Der Port muss zwischen 1 und 65535 liegen.';

  @override
  String get observantMixedContentTitle =>
      'Blockiert: Diese https-Seite kann keine http-Adresse erreichen (gemischte Inhalte)';

  @override
  String observantMixedContentBody(String address) {
    return 'Browser blockieren jede Anfrage einer über https geladenen Seite an eine reine http-Adresse, daher wurde $address nicht gefragt. Entweder:';
  }

  @override
  String get observantMixedContentFixHttps =>
      'ObservANT über https ausliefern (scripts/linux/observant/serve.sh oder ein Reverse Proxy, dessen Name in allowed_hosts von ObservANT steht) und seine https://-Adresse eintragen, oder';

  @override
  String observantMixedContentFixHttp(String address) {
    return 'die App im eigenen Netz über http öffnen: Die eigene Seite der Kamera unter $address liefert sie aus.';
  }

  @override
  String observantLocalNetworkRefused(String address) {
    return 'Der Zugriff auf das lokale Netzwerk ist für diese Website blockiert, daher verweigert Chrome jede Anfrage an $address. Zum Erlauben: auf das Symbol links neben der Adressleiste klicken, Website-Einstellungen öffnen, Zugriff auf lokales Netzwerk auf Zulassen stellen und erneut prüfen.';
  }

  @override
  String observantAddressUnreachable(String address, String origin) {
    return '$address gab keine Antwort, die diese Seite lesen darf. Prüfen Sie die Adresse und ob ObservANT dort läuft. ObservANT antwortet einer anderen Seite nur, wenn deren Ursprung $origin in seiner read_origins-Liste steht.';
  }

  @override
  String get observantUnreachableLocalNetwork =>
      'Falls Chrome nach dem Zugriff auf das lokale Netzwerk gefragt hat und die Frage geschlossen wurde, erneut prüfen und Zulassen wählen.';

  @override
  String observantTimedOut(String address, String seconds) {
    return '$address hat nicht innerhalb von $seconds s geantwortet.';
  }

  @override
  String observantRefusedStatus(String address, String status, String reason) {
    return '$address lehnte mit HTTP $status ab: $reason';
  }

  @override
  String observantNotObservant(String address) {
    return '$address hat geantwortet, aber nicht als ObservANT-Kamera.';
  }
}
