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
      'Note: on the web, sqlite3.wasm must be served beside the page (the build copies web/sqlite3.wasm there).';

  @override
  String detectionInView(String what) {
    return '$what in view';
  }

  @override
  String detectionLastSeen(String when) {
    return 'Last seen: $when';
  }

  @override
  String get detectionNotSeenYet => 'Nothing seen yet';

  @override
  String get detectionLastArrival => 'The last arrival';

  @override
  String get detectionArrivalVideo => 'Watch the arrival';

  @override
  String get detectionEarlierVideos => 'Earlier videos:';

  @override
  String get cameraSettingsNav => 'Camera';

  @override
  String get cameraSettingsTitle => 'Camera settings';

  @override
  String get cameraNotReachable =>
      'No ObservANT camera answers here. These settings live on an ObservANT camera\'s own page.';

  @override
  String get cameraRotation => 'Rotation';

  @override
  String get cameraSensitivity => 'Detection sensitivity';

  @override
  String get cameraSensitivityHelp =>
      'Higher means fewer false alarms; lower finds one in poor light too.';

  @override
  String get cameraName => 'Name';

  @override
  String get cameraSave => 'Save';

  @override
  String get cameraSaved => 'Saved';

  @override
  String get cameraSaveFailed => 'Could not save';

  @override
  String get cameraInfo => 'Camera info';

  @override
  String get cameraDevice => 'Camera';

  @override
  String get cameraResolution => 'Resolution';

  @override
  String get cameraFrameRate => 'Frame rate';

  @override
  String get cameraDetection => 'Detection';

  @override
  String get cameraOn => 'on';

  @override
  String get cameraOff => 'off';

  @override
  String get cameraModelRuns => 'Model runs';

  @override
  String get cameraVisits => 'Visits counted';

  @override
  String cameraLastScore(int percent) {
    return 'Last detection: $percent %';
  }

  @override
  String observantProblem(String problem) {
    return 'The camera has a problem: $problem';
  }

  @override
  String get cameraProblem => 'Problem';

  @override
  String get cameraFalseAlarm => 'False alarm';

  @override
  String get cameraFalseAlarmHelp =>
      'Ignores the boxed spot from now on, such as a drying rack the camera takes for a cat.';

  @override
  String cameraIgnoredSpots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spots are ignored (grey on the preview)',
      one: '1 spot is ignored (grey on the preview)',
    );
    return '$_temp0';
  }

  @override
  String get cameraWatchAgain => 'Watch again';

  @override
  String observantUnreachable(String time) {
    return 'Camera unreachable since $time';
  }

  @override
  String detectionAllVisits(int count) {
    return 'All $count visits';
  }

  @override
  String get detectionFewerVisits => 'Fewer visits';

  @override
  String get observantOthers => 'Other cameras';

  @override
  String get observantPeerUnreachable => 'Not reachable';

  @override
  String get cameraVersion => 'Version';

  @override
  String get cameraPrivacy => 'Privacy filter';

  @override
  String get cameraPrivacyPixelate =>
      'pixelates all but the detected animals (set in the settings file)';

  @override
  String get cameraPrivacyOff => 'off (set in the settings file)';

  @override
  String get cameraClasses => 'What it detects';

  @override
  String get cameraAddClass => 'Add a class';

  @override
  String get cameraClassesHelp =>
      'Visits, notifications and boxes count these objects (COCO classes; cat is the default). A change applies at the next model run. The privacy filter keeps every one of them sharp, people too.';

  @override
  String get cameraClassesLocked =>
      'The privacy filter is on, so only the settings file (observant.toml) can change these.';

  @override
  String get cameraRetry => 'Try again';

  @override
  String get detectionTooDark =>
      'Too dark: the camera sees black and detects nothing';

  @override
  String get devStats => 'Stats';

  @override
  String get devStatsNone =>
      'No numbers yet: the camera reports none, and the browser plays nothing.';

  @override
  String get devStatsCamera => 'Camera';

  @override
  String devStatsCameraValue(String fps, String configured) {
    return '$fps of $configured fps';
  }

  @override
  String get devStatsModel => 'Detection';

  @override
  String devStatsModelValue(String ms, String rate) {
    return '$ms ms per run, $rate runs/s';
  }

  @override
  String get devStatsCpu => 'CPU';

  @override
  String devStatsCpuValue(String percent, String cores, String load) {
    return '$percent % of one core, $cores cores, load $load';
  }

  @override
  String get devStatsMemory => 'Memory';

  @override
  String get devStatsTemperature => 'Temperature';

  @override
  String get devStatsUptime => 'Running for';

  @override
  String devStatsUptimeValue(String hours, String minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get devStatsViewers => 'Viewers';

  @override
  String get devStatsBrowser => 'This browser';

  @override
  String devStatsBrowserValue(String fps, String size, String dropped) {
    return '$fps fps, $size, $dropped dropped';
  }

  @override
  String get observantPixelated =>
      'Privacy filter on: everything but the detected animals is pixelated';

  @override
  String get cameraRecentDetections => 'Recent detections';

  @override
  String get cameraRecentDetectionsHelp =>
      'Was one of them a false alarm? Mark it, and the camera ignores that spot from now on.';

  @override
  String get cameraWasFalseAlarm => 'False alarm';

  @override
  String get cameraSpotIgnored => 'Ignored';

  @override
  String cameraScoreValue(int percent) {
    return 'A detection counts from $percent % certainty';
  }

  @override
  String get cameraRotateLeft => 'Turn the picture left';

  @override
  String get cameraRotateRight => 'Turn the picture right';

  @override
  String detectionVideoFrom(String time) {
    return 'Video from $time';
  }

  @override
  String detectionRecentVisits(String visits) {
    return 'Recent visits: $visits';
  }

  @override
  String detectionVisitStay(String time, String minutes) {
    return '$time ($minutes min)';
  }

  @override
  String get webrtcConnecting => 'Connecting to the signalling server';

  @override
  String get webrtcWaitingForCamera => 'Waiting for a camera';

  @override
  String get webrtcNegotiating => 'Negotiating the video stream';

  @override
  String get webrtcStreaming => 'Streaming';

  @override
  String get webrtcFailed => 'The stream could not be started';

  @override
  String webrtcSignallingLost(int ms) {
    return 'Lost the signalling connection — retrying every $ms ms.';
  }

  @override
  String get webrtcCameraGone => 'The camera went offline.';

  @override
  String webrtcNoSession(String camera) {
    return 'Could not open a session for the camera $camera.';
  }

  @override
  String get webrtcPeerError =>
      'The connection reported an error. If the camera is another device, check that the WebRTC UDP range reaches it.';

  @override
  String get webrtcPeerNotStarted => 'Could not start the connection.';

  @override
  String get webrtcNoCamera =>
      'Signalling is up, but no camera has announced itself. Start kataglyphis_observant on the camera host.';

  @override
  String get webrtcExchangingCandidates => 'Exchanging ICE candidates.';

  @override
  String get webrtcSeeConsole =>
      'See the browser console for the underlying error.';

  @override
  String get visitStats => 'Visits';

  @override
  String visitStatsNone(int days) {
    return 'No visits in the last $days days.';
  }

  @override
  String visitStatsSummary(int today, int total, int days) {
    return '$today today, $total in $days days';
  }

  @override
  String visitStatsAverageStay(String minutes) {
    return 'Average stay: $minutes min';
  }

  @override
  String get visitStatsPerDay => 'Per day';

  @override
  String get visitStatsPerHour => 'By time of day';
}
