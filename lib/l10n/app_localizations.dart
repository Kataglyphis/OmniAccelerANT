import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @homepage.
  ///
  /// In en, this message translates to:
  /// **'Homepage'**
  String get homepage;

  /// No description provided for @aboutme.
  ///
  /// In en, this message translates to:
  /// **'About me'**
  String get aboutme;

  /// No description provided for @quotations.
  ///
  /// In en, this message translates to:
  /// **'Quotations'**
  String get quotations;

  /// No description provided for @books.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get books;

  /// No description provided for @games.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get games;

  /// No description provided for @gamesDescription.
  ///
  /// In en, this message translates to:
  /// **'Funny Games and what there is to know about'**
  String get gamesDescription;

  /// No description provided for @booksDescription.
  ///
  /// In en, this message translates to:
  /// **'Books worth reading'**
  String get booksDescription;

  /// No description provided for @films.
  ///
  /// In en, this message translates to:
  /// **'Films'**
  String get films;

  /// No description provided for @filmsDescription.
  ///
  /// In en, this message translates to:
  /// **'Films worth watching'**
  String get filmsDescription;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @stream.
  ///
  /// In en, this message translates to:
  /// **'Stream'**
  String get stream;

  /// No description provided for @quotationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Collection of various quotations I am inspired by or just can laugh about'**
  String get quotationsDescription;

  /// No description provided for @aiPlayground.
  ///
  /// In en, this message translates to:
  /// **'AI Playground'**
  String get aiPlayground;

  /// No description provided for @renderingPlayground.
  ///
  /// In en, this message translates to:
  /// **'Rendering Playground'**
  String get renderingPlayground;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Visit page'**
  String get follow;

  /// No description provided for @rerunSqliteHealthcheck.
  ///
  /// In en, this message translates to:
  /// **'Re-run SQLite Healthcheck'**
  String get rerunSqliteHealthcheck;

  /// No description provided for @sqliteError.
  ///
  /// In en, this message translates to:
  /// **'SQLite Error'**
  String get sqliteError;

  /// No description provided for @sqliteWebHint.
  ///
  /// In en, this message translates to:
  /// **'Note: on the web, sqlite3.wasm must be served beside the page (the build copies web/sqlite3.wasm there).'**
  String get sqliteWebHint;

  /// No description provided for @catInView.
  ///
  /// In en, this message translates to:
  /// **'Cat in view'**
  String get catInView;

  /// No description provided for @catLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Cat last seen: {when}'**
  String catLastSeen(String when);

  /// No description provided for @catNotSeenYet.
  ///
  /// In en, this message translates to:
  /// **'No cat seen yet'**
  String get catNotSeenYet;

  /// No description provided for @catLastArrival.
  ///
  /// In en, this message translates to:
  /// **'The cat\'s last arrival'**
  String get catLastArrival;

  /// No description provided for @catArrivalVideo.
  ///
  /// In en, this message translates to:
  /// **'Watch the arrival'**
  String get catArrivalVideo;

  /// No description provided for @catEarlierVideos.
  ///
  /// In en, this message translates to:
  /// **'Earlier videos:'**
  String get catEarlierVideos;

  /// No description provided for @cameraSettingsNav.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraSettingsNav;

  /// No description provided for @cameraSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera settings'**
  String get cameraSettingsTitle;

  /// No description provided for @cameraNotReachable.
  ///
  /// In en, this message translates to:
  /// **'No cat cam answers here. These settings live on a cat cam\'s own page.'**
  String get cameraNotReachable;

  /// No description provided for @cameraRotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get cameraRotation;

  /// No description provided for @cameraSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Detection sensitivity'**
  String get cameraSensitivity;

  /// No description provided for @cameraSensitivityHelp.
  ///
  /// In en, this message translates to:
  /// **'Higher means fewer false alarms; lower spots a cat in poor light too.'**
  String get cameraSensitivityHelp;

  /// No description provided for @cameraName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get cameraName;

  /// No description provided for @cameraSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get cameraSave;

  /// No description provided for @cameraSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get cameraSaved;

  /// No description provided for @cameraSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save'**
  String get cameraSaveFailed;

  /// No description provided for @cameraInfo.
  ///
  /// In en, this message translates to:
  /// **'Camera info'**
  String get cameraInfo;

  /// No description provided for @cameraDevice.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraDevice;

  /// No description provided for @cameraResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get cameraResolution;

  /// No description provided for @cameraFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get cameraFrameRate;

  /// No description provided for @cameraDetection.
  ///
  /// In en, this message translates to:
  /// **'Cat detection'**
  String get cameraDetection;

  /// No description provided for @cameraOn.
  ///
  /// In en, this message translates to:
  /// **'on'**
  String get cameraOn;

  /// No description provided for @cameraOff.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get cameraOff;

  /// No description provided for @cameraModelRuns.
  ///
  /// In en, this message translates to:
  /// **'Model runs'**
  String get cameraModelRuns;

  /// No description provided for @cameraVisits.
  ///
  /// In en, this message translates to:
  /// **'Visits counted'**
  String get cameraVisits;

  /// Under the detection slider: the best score of the last detection, real or false, to set the slider just above a false one.
  ///
  /// In en, this message translates to:
  /// **'Last detection: {percent} %'**
  String cameraLastScore(int percent);

  /// Under the cat cam name when its /healthz says it is not ok; the problem is the cat cam's own English text.
  ///
  /// In en, this message translates to:
  /// **'The camera has a problem: {problem}'**
  String catCamProblem(String problem);

  /// No description provided for @cameraProblem.
  ///
  /// In en, this message translates to:
  /// **'Problem'**
  String get cameraProblem;

  /// Button under the camera preview: the boxed spots are no cat and are ignored from now on.
  ///
  /// In en, this message translates to:
  /// **'Not a cat'**
  String get cameraNotACat;

  /// No description provided for @cameraNotACatHelp.
  ///
  /// In en, this message translates to:
  /// **'Ignores the boxed spot from now on, such as a drying rack the camera takes for a cat.'**
  String get cameraNotACatHelp;

  /// How many spots were marked "not a cat"; they show grey over the preview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 spot is ignored (grey on the preview)} other{{count} spots are ignored (grey on the preview)}}'**
  String cameraIgnoredSpots(int count);

  /// Button beside the ignored spots: forget them all.
  ///
  /// In en, this message translates to:
  /// **'Watch again'**
  String get cameraWatchAgain;

  /// Under the cat cam name once its /healthz stopped answering; time is when it stopped.
  ///
  /// In en, this message translates to:
  /// **'Camera unreachable since {time}'**
  String catCamUnreachable(String time);

  /// Button under the three latest visits: shows the whole visit log.
  ///
  /// In en, this message translates to:
  /// **'All {count} visits'**
  String catAllVisits(int count);

  /// Button under the whole visit log: back to the three latest.
  ///
  /// In en, this message translates to:
  /// **'Fewer visits'**
  String get catFewerVisits;

  /// Heading over the other cat cams this one lists as peers.
  ///
  /// In en, this message translates to:
  /// **'Other cat cams'**
  String get catOtherCameras;

  /// Under another cat cam that does not answer this page.
  ///
  /// In en, this message translates to:
  /// **'Not reachable'**
  String get catPeerUnreachable;

  /// Row of the camera info table: the cat cam build.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get cameraVersion;

  /// Row of the camera info table: whether the cat cam pixelates all but the detected animals.
  ///
  /// In en, this message translates to:
  /// **'Privacy filter'**
  String get cameraPrivacy;

  /// Value of the privacy filter row when privacy = "pixelate".
  ///
  /// In en, this message translates to:
  /// **'pixelates all but the detected animals (set in the settings file)'**
  String get cameraPrivacyPixelate;

  /// Value of the privacy filter row when the filter is off.
  ///
  /// In en, this message translates to:
  /// **'off (set in the settings file)'**
  String get cameraPrivacyOff;

  /// Heading on the Camera page above the watched object classes.
  ///
  /// In en, this message translates to:
  /// **'What it detects'**
  String get cameraClasses;

  /// Hint of the menu that adds a watched class.
  ///
  /// In en, this message translates to:
  /// **'Add a class'**
  String get cameraAddClass;

  /// Help under the watched classes on the Camera page.
  ///
  /// In en, this message translates to:
  /// **'Visits, notifications and boxes count these objects (COCO classes; cat is the default). A change applies at the next model run. The privacy filter keeps every one of them sharp, people too.'**
  String get cameraClassesHelp;

  /// Button on the Stream page that opens the panel of performance numbers.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get devStats;

  /// The stats panel before any number arrived.
  ///
  /// In en, this message translates to:
  /// **'No numbers yet: the camera reports none, and the browser plays nothing.'**
  String get devStatsNone;

  /// Stats row: frames the camera delivers per second.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get devStatsCamera;

  /// Measured frames per second of the configured rate.
  ///
  /// In en, this message translates to:
  /// **'{fps} of {configured} fps'**
  String devStatsCameraValue(String fps, String configured);

  /// Stats row: the model's time per run and its runs per second.
  ///
  /// In en, this message translates to:
  /// **'Detection'**
  String get devStatsModel;

  /// Milliseconds per model run and runs per second.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms per run, {rate} runs/s'**
  String devStatsModelValue(String ms, String rate);

  /// Stats row: the cat cam's CPU use and the system load.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get devStatsCpu;

  /// Process CPU in percent of one core, the core count, the 1-minute load average.
  ///
  /// In en, this message translates to:
  /// **'{percent} % of one core, {cores} cores, load {load}'**
  String devStatsCpuValue(String percent, String cores, String load);

  /// Stats row: the cat cam's resident memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get devStatsMemory;

  /// Stats row: the board's CPU temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get devStatsTemperature;

  /// Stats row: how long the cat cam has run.
  ///
  /// In en, this message translates to:
  /// **'Running for'**
  String get devStatsUptime;

  /// Uptime in hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String devStatsUptimeValue(String hours, String minutes);

  /// Stats row: browser tabs on the stream.
  ///
  /// In en, this message translates to:
  /// **'Viewers'**
  String get devStatsViewers;

  /// Stats row: what this browser plays.
  ///
  /// In en, this message translates to:
  /// **'This browser'**
  String get devStatsBrowser;

  /// Frames per second received, picture size, frames dropped so far.
  ///
  /// In en, this message translates to:
  /// **'{fps} fps, {size}, {dropped} dropped'**
  String devStatsBrowserValue(String fps, String size, String dropped);

  /// Under the cat cam name when its /healthz says privacy is pixelate.
  ///
  /// In en, this message translates to:
  /// **'Privacy filter on: everything but the detected animals is pixelated'**
  String get catCamPixelated;

  /// Heading over the pictures of the latest arrivals on the Camera page.
  ///
  /// In en, this message translates to:
  /// **'Recent detections'**
  String get cameraRecentDetections;

  /// No description provided for @cameraRecentDetectionsHelp.
  ///
  /// In en, this message translates to:
  /// **'Was one of them not a cat? Mark it, and the camera ignores that spot from now on.'**
  String get cameraRecentDetectionsHelp;

  /// Button under a recent arrival: its boxes become spots the camera ignores.
  ///
  /// In en, this message translates to:
  /// **'Not a cat'**
  String get cameraWasNotACat;

  /// Under a recent arrival whose spots are already ignored.
  ///
  /// In en, this message translates to:
  /// **'Ignored'**
  String get cameraSpotIgnored;

  /// Text under the detection sensitivity slider.
  ///
  /// In en, this message translates to:
  /// **'A cat counts from {percent} % certainty'**
  String cameraScoreValue(int percent);

  /// No description provided for @catRotateLeft.
  ///
  /// In en, this message translates to:
  /// **'Turn the picture left'**
  String get catRotateLeft;

  /// No description provided for @catRotateRight.
  ///
  /// In en, this message translates to:
  /// **'Turn the picture right'**
  String get catRotateRight;

  /// What a screen reader says for an earlier video's play link.
  ///
  /// In en, this message translates to:
  /// **'Video from {time}'**
  String catVideoFrom(String time);

  /// No description provided for @catRecentVisits.
  ///
  /// In en, this message translates to:
  /// **'Recent visits: {visits}'**
  String catRecentVisits(String visits);

  /// No description provided for @catVisitStay.
  ///
  /// In en, this message translates to:
  /// **'{time} ({minutes} min)'**
  String catVisitStay(String time, String minutes);

  /// No description provided for @webrtcConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the signalling server'**
  String get webrtcConnecting;

  /// No description provided for @webrtcWaitingForCamera.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a camera'**
  String get webrtcWaitingForCamera;

  /// No description provided for @webrtcNegotiating.
  ///
  /// In en, this message translates to:
  /// **'Negotiating the video stream'**
  String get webrtcNegotiating;

  /// No description provided for @webrtcStreaming.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get webrtcStreaming;

  /// No description provided for @webrtcFailed.
  ///
  /// In en, this message translates to:
  /// **'The stream could not be started'**
  String get webrtcFailed;

  /// No description provided for @webrtcSignallingLost.
  ///
  /// In en, this message translates to:
  /// **'Lost the signalling connection — retrying every {ms} ms.'**
  String webrtcSignallingLost(int ms);

  /// No description provided for @webrtcCameraGone.
  ///
  /// In en, this message translates to:
  /// **'The camera went offline.'**
  String get webrtcCameraGone;

  /// No description provided for @webrtcNoSession.
  ///
  /// In en, this message translates to:
  /// **'Could not open a session for the camera {camera}.'**
  String webrtcNoSession(String camera);

  /// No description provided for @webrtcPeerError.
  ///
  /// In en, this message translates to:
  /// **'The connection reported an error. If the camera is another device, check that the WebRTC UDP range reaches it.'**
  String get webrtcPeerError;

  /// No description provided for @webrtcPeerNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Could not start the connection.'**
  String get webrtcPeerNotStarted;

  /// No description provided for @webrtcNoCamera.
  ///
  /// In en, this message translates to:
  /// **'Signalling is up, but no camera has announced itself. Start kataglyphis_cat_webrtc on the camera host.'**
  String get webrtcNoCamera;

  /// No description provided for @webrtcExchangingCandidates.
  ///
  /// In en, this message translates to:
  /// **'Exchanging ICE candidates.'**
  String get webrtcExchangingCandidates;

  /// No description provided for @webrtcSeeConsole.
  ///
  /// In en, this message translates to:
  /// **'See the browser console for the underlying error.'**
  String get webrtcSeeConsole;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
