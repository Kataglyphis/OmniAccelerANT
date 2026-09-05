import 'package:flutter/material.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

import 'package:go_router/go_router.dart';

import 'package:omni_accelerant/Pages/Footer/jotrockenmitlocken_footer.dart';
import 'package:omni_accelerant/Routing/jotrockenmitlocken_router.dart';
import 'package:omni_accelerant/Pages/Home/home_config.dart';
import 'package:omni_accelerant/Pages/jotrockenmitlocken_screen_configurations.dart';
import 'package:omni_accelerant/blog_dependent_app_attributes.dart';
import 'package:omni_accelerant/blog_page_config.dart';
import 'package:omni_accelerant/my_two_cents_config.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/app_settings.dart';
import 'package:anthology/constants.dart';
import 'package:anthology/Routing/router_creater.dart';
import 'package:anthology/user_settings.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with SingleTickerProviderStateMixin {
  ThemeMode themeMode = ThemeMode.dark;
  ColorSeed colorSelected = ColorSeed.baseColor;
  int currentLanguageIndex = 0;
  int currentPageIndex = 0;

  bool get useLightMode {
    switch (themeMode) {
      case ThemeMode.system:
        return View.of(context).platformDispatcher.platformBrightness ==
            Brightness.light;
      case ThemeMode.light:
        return true;
      case ThemeMode.dark:
        return false;
    }
  }

  late final AnimationController controller;
  late final CurvedAnimation railAnimation;
  late Future<
    (
      AppSettings,
      UserSettings,
      List<BlogPageConfig>,
      List<MyTwoCentsConfig>,
      WebRTCSettings,
    )
  >
  _settings;
  final String userSettingsFilePath =
      "assets/settings/user_settings/global_user_settings.json";
  final String appSettingsFilePath = "assets/settings/app_settings.json";
  final String blogSettingsFilePath = "assets/settings/blog_settings.json";
  final String twoCentsSettingsFilePath =
      "assets/settings/my_two_cents_settings.json";
  final String webrtcSettingsFilePath = "assets/settings/webrtc_settings.json";
  bool controllerInitialized = false;
  bool showMediumSizeLayout = false;
  bool showLargeSizeLayout = false;

  @override
  initState() {
    super.initState();
    controller = AnimationController(
      duration: Duration(milliseconds: transitionLength.toInt() * 2),
      value: 0,
      vsync: this,
    );
    railAnimation = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.5, 1.0),
    );
    _settings = _loadAppSettings();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final double width = MediaQuery.of(context).size.width;
    final AnimationStatus status = controller.status;
    if (width > mediumWidthBreakpoint) {
      if (width > largeWidthBreakpoint) {
        showMediumSizeLayout = false;
        showLargeSizeLayout = true;
      } else {
        showMediumSizeLayout = true;
        showLargeSizeLayout = false;
      }
      if (status != AnimationStatus.forward &&
          status != AnimationStatus.completed) {
        controller.forward();
      }
    } else {
      showMediumSizeLayout = false;
      showLargeSizeLayout = false;
      if (status != AnimationStatus.reverse &&
          status != AnimationStatus.dismissed) {
        controller.reverse();
      }
    }
    if (!controllerInitialized) {
      controllerInitialized = true;
      controller.value = width > mediumWidthBreakpoint ? 1 : 0;
    }
  }

  /// Loads all application settings in parallel for improved startup performance.
  ///
  /// Returns a tuple of (AppSettings, UserSettings, BlogConfigs, TwoCentsConfigs, WebRTCSettings).
  /// Throws [FormatException] if any JSON file is malformed.
  Future<
    (
      AppSettings,
      UserSettings,
      List<BlogPageConfig>,
      List<MyTwoCentsConfig>,
      WebRTCSettings,
    )
  >
  _loadAppSettings() async {
    // Load all JSON files in parallel for better performance
    final results = await Future.wait([
      rootBundle.loadString(userSettingsFilePath),
      rootBundle.loadString(appSettingsFilePath),
      rootBundle.loadString(blogSettingsFilePath),
      rootBundle.loadString(twoCentsSettingsFilePath),
      rootBundle.loadString(webrtcSettingsFilePath),
    ]);

    final userSettingsJson = json.decode(results[0]) as Map<String, dynamic>;
    final appSettingsJson = json.decode(results[1]) as Map<String, dynamic>;
    final blogSettingsJson = json.decode(results[2]) as List<dynamic>;
    final twoCentsSettingsJson = json.decode(results[3]) as List<dynamic>;
    final webrtcSettingsJson = json.decode(results[4]) as Map<String, dynamic>;

    final userSettings = UserSettings.fromJsonFile(userSettingsJson);
    final appSettings = AppSettings.fromJsonFile(appSettingsJson);

    final blogConfigs = blogSettingsJson
        .map((e) => BlogPageConfig.fromJsonFile(e as Map<String, dynamic>))
        .toList();

    final twoCentsConfigs = twoCentsSettingsJson
        .map((e) => MyTwoCentsConfig.fromJsonFile(e as Map<String, dynamic>))
        .toList();

    final webrtcSettings = WebRTCSettings.fromJsonFile(webrtcSettingsJson);

    return (
      appSettings,
      userSettings,
      blogConfigs,
      twoCentsConfigs,
      webrtcSettings,
    );
  }

  void handleBrightnessChange(bool useLightMode) {
    setState(() {
      themeMode = useLightMode ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void handlePageChange(int pageIndex) {
    currentPageIndex = pageIndex;
  }

  void handleLanguageSelect(int index) {
    setState(() {
      currentLanguageIndex = index;
    });
  }

  void handleColorSelect(int value) {
    setState(() {
      colorSelected = ColorSeed.values[value];
    });
  }

  final List<LocalizationsDelegate> localizationsDelegate = const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  @override
  Widget build(BuildContext context) {
    ThemeData darkTheme = ThemeData(
      fontFamily: 'Roboto',
      colorSchemeSeed: colorSelected.color,
      useMaterial3: true,
      brightness: Brightness.dark,
    );
    ThemeData lightTheme = ThemeData(
      fontFamily: 'Roboto',
      colorSchemeSeed: colorSelected.color,
      useMaterial3: true,
      brightness: Brightness.light,
    );
    return FutureBuilder(
      future: _settings,
      builder: (context, data) {
        if (data.hasData) {
          JotrockenmitLockenScreenConfigurations screenConfigurations =
              JotrockenmitLockenScreenConfigurations.fromBlogAndDataConfigs(
                blogPageConfigs: data.requireData.$3,
                twoCentsConfigs: data.requireData.$4,
              );
          BlogDependentAppAttributes blogDependentAppAttributes =
              BlogDependentAppAttributes(
                blogDependentScreenConfigurations: screenConfigurations,
                twoCentsConfigs: data.requireData.$4,
                blockSettings: data.requireData.$3,
                webrtcSettings: data.requireData.$5,
              );
          AppAttributes appAttributes = AppAttributes(
            footerConfig: JoTrockenMitLockenFooterConfig(),
            homeConfig: JotrockenMitLockenHomeConfig(),
            appSettings: data.requireData.$1,
            userSettings: data.requireData.$2,
            screenConfigurations: screenConfigurations,
            railAnimation: railAnimation,
            showMediumSizeLayout: showMediumSizeLayout,
            showLargeSizeLayout: showLargeSizeLayout,
            currentLanguageIndex: currentLanguageIndex,
            useLightMode: useLightMode,
            colorSelected: colorSelected,
            handleBrightnessChange: handleBrightnessChange,
            handleLanguageSelect: handleLanguageSelect,
            handleColorSelect: handleColorSelect,
          );

          RoutesCreator routesCreator = JotrockenMitLockenRoutes(
            blogDependentAppAttributes: blogDependentAppAttributes,
          );

          final GoRouter routerConfig = routesCreator.getRouterConfig(
            appAttributes,
            controller,
            handlePageChange,
            currentPageIndex,
          );
          var supportedLanguages = data.requireData.$1.supportedLocales!
              .map((element) => Locale(element))
              .toList();
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: localizationsDelegate,
            onGenerateTitle: (context) =>
                (Localizations.localeOf(context) == const Locale("de"))
                ? appAttributes.appSettings.appTitleDe
                : appAttributes.appSettings.appTitleEn,
            themeMode: themeMode,
            locale: supportedLanguages[0],
            supportedLocales: supportedLanguages,
            theme: lightTheme,
            darkTheme: darkTheme,
            routerConfig: routerConfig,
          );
        } else if (data.hasError) {
          // Display user-friendly error with details for debugging
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to load application settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${data.error}',
                        style: TextStyle(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else {
          return Center(
            child: CircularProgressIndicator(color: ColorSeed.baseColor.color),
          );
        }
      },
    );
  }
}
