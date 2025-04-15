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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// Switch between dark and light mode!
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

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

  /// No description provided for @blockEntryOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview of all my blog posts'**
  String get blockEntryOverview;

  /// No description provided for @blockEntryOverviewDescription.
  ///
  /// In en, this message translates to:
  /// **'Does not include reviews of books/movies/games'**
  String get blockEntryOverviewDescription;

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

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @quotationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Collection of various quotations I am inspired by or just can laugh about'**
  String get quotationsDescription;

  /// No description provided for @switchLang.
  ///
  /// In en, this message translates to:
  /// **'Switch (DE/EN)'**
  String get switchLang;

  /// No description provided for @mailMe.
  ///
  /// In en, this message translates to:
  /// **'Mail Me'**
  String get mailMe;

  /// No description provided for @shortDescriptionTextMyPersona.
  ///
  /// In en, this message translates to:
  /// **'Interested in many things. I love breathing life into artificial neurons.'**
  String get shortDescriptionTextMyPersona;

  /// No description provided for @sleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleep;

  /// No description provided for @studying.
  ///
  /// In en, this message translates to:
  /// **'Studying'**
  String get studying;

  /// No description provided for @sports.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get sports;

  /// No description provided for @meditation.
  ///
  /// In en, this message translates to:
  /// **'Meditation'**
  String get meditation;

  /// No description provided for @guitar.
  ///
  /// In en, this message translates to:
  /// **'Guitar'**
  String get guitar;

  /// No description provided for @familyFriends.
  ///
  /// In en, this message translates to:
  /// **'Family&Friends'**
  String get familyFriends;

  /// No description provided for @spendCoffe.
  ///
  /// In en, this message translates to:
  /// **'You can get me some coffee'**
  String get spendCoffe;

  /// No description provided for @toogleLanguage.
  ///
  /// In en, this message translates to:
  /// **'Toggle language'**
  String get toogleLanguage;

  /// No description provided for @toogleBrightness.
  ///
  /// In en, this message translates to:
  /// **'Toggle brightness'**
  String get toogleBrightness;

  /// No description provided for @selectSeedColor.
  ///
  /// In en, this message translates to:
  /// **'Select a seed color'**
  String get selectSeedColor;

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

  /// No description provided for @playgroundDescription.
  ///
  /// In en, this message translates to:
  /// **'Visit my code repo'**
  String get playgroundDescription;

  /// No description provided for @myPerfectDay.
  ///
  /// In en, this message translates to:
  /// **'My perfect Day'**
  String get myPerfectDay;

  /// No description provided for @imprint.
  ///
  /// In en, this message translates to:
  /// **'Imprint'**
  String get imprint;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @cookieStatement.
  ///
  /// In en, this message translates to:
  /// **'Cookie statement'**
  String get cookieStatement;

  /// No description provided for @declarationOnAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Declaration on accessibility'**
  String get declarationOnAccessibility;

  /// No description provided for @disclaimer.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer: I accept no liability for the content of external links.'**
  String get disclaimer;

  /// No description provided for @copyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright © 2024 Jonas Heinle. \nAll rights reserved.'**
  String get copyright;

  /// No description provided for @copyrightFooterTitle.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get copyrightFooterTitle;

  /// No description provided for @visitBlogEntry.
  ///
  /// In en, this message translates to:
  /// **'Visit blog entry'**
  String get visitBlogEntry;

  /// No description provided for @externalLinks.
  ///
  /// In en, this message translates to:
  /// **'External links'**
  String get externalLinks;

  /// No description provided for @lastModified.
  ///
  /// In en, this message translates to:
  /// **'Last modified'**
  String get lastModified;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Visit page'**
  String get follow;

  /// No description provided for @entryRedirectText.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get entryRedirectText;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
