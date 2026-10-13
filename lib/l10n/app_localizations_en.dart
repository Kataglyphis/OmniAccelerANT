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
  String get catInView => 'Cat in view';

  @override
  String catLastSeen(String when) {
    return 'Cat last seen: $when';
  }

  @override
  String get catNotSeenYet => 'No cat seen yet';

  @override
  String get catLastArrival => 'The cat\'s last arrival';

  @override
  String get catArrivalVideo => 'Watch the arrival';

  @override
  String get catEarlierVideos => 'Earlier videos:';

  @override
  String get cameraSettingsNav => 'Camera';

  @override
  String get cameraSettingsTitle => 'Camera settings';

  @override
  String get cameraNotReachable =>
      'No cat cam answers here. These settings live on a cat cam\'s own page.';

  @override
  String get cameraRotation => 'Rotation';

  @override
  String get cameraSensitivity => 'Detection sensitivity';

  @override
  String get cameraSensitivityHelp =>
      'Higher means fewer false alarms; lower spots a cat in poor light too.';

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
  String get cameraDetection => 'Cat detection';

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
  String catCamProblem(String problem) {
    return 'The camera has a problem: $problem';
  }

  @override
  String get cameraProblem => 'Problem';

  @override
  String cameraScoreValue(int percent) {
    return 'A cat counts from $percent % certainty';
  }

  @override
  String get catRotateLeft => 'Turn the picture left';

  @override
  String get catRotateRight => 'Turn the picture right';

  @override
  String catVideoFrom(String time) {
    return 'Video from $time';
  }

  @override
  String catRecentVisits(String visits) {
    return 'Recent visits: $visits';
  }

  @override
  String catVisitStay(String time, String minutes) {
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
      'Signalling is up, but no camera has announced itself. Start kataglyphis_cat_webrtc on the camera host.';

  @override
  String get webrtcExchangingCandidates => 'Exchanging ICE candidates.';

  @override
  String get webrtcSeeConsole =>
      'See the browser console for the underlying error.';
}
