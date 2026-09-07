// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:anthology/Pages/Footer/default_footer_config.dart';
import 'package:anthology/Pages/Home/default_home_config.dart';
import 'package:anthology/app_settings.dart';
import 'package:anthology/app_shell.dart';
import 'package:anthology/blog_page_config.dart';
import 'package:anthology/my_two_cents_config.dart';
import 'package:anthology/user_settings.dart';

import 'package:omni_accelerant/Pages/jotrockenmitlocken_screen_configurations.dart';
import 'package:omni_accelerant/Routing/jotrockenmitlocken_router.dart';
import 'package:omni_accelerant/blog_dependent_app_attributes.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

/// Everything this app reads off disk before its first frame.
///
/// The fifth slot is what makes it OmniAccelerANT's own type rather than the
/// shell's: [WebRTCSettings] exists only in this app.
typedef OmniBootstrapData = (
  AppSettings,
  UserSettings,
  List<BlogPageConfig>,
  List<MyTwoCentsConfig>,
  WebRTCSettings,
);

const String userSettingsFilePath =
    "assets/settings/user_settings/global_user_settings.json";
const String appSettingsFilePath = "assets/settings/app_settings.json";
const String blogSettingsFilePath = "assets/settings/blog_settings.json";
const String twoCentsSettingsFilePath =
    "assets/settings/my_two_cents_settings.json";
const String webrtcSettingsFilePath = "assets/settings/webrtc_settings.json";

/// Loads all application settings in parallel for improved startup performance.
///
/// Returns a tuple of (AppSettings, UserSettings, BlogConfigs, TwoCentsConfigs,
/// WebRTCSettings). Throws [FormatException] if any JSON file is malformed.
Future<OmniBootstrapData> loadAppSettings() async {
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

Future<void> main() async {
  await RustLib.init();
  runApp(const App());
}

/// OmniAccelerANT's half of the shared shell.
///
/// Everything that used to live here - the animation controller, the width
/// breakpoints, the four `handle*` callbacks, the theme pair and the
/// `FutureBuilder -> MaterialApp.router` tail - now lives once in
/// [KataglyphisAppShell]. What is left is genuinely this app's: its settings
/// loader, its generated `AppLocalizations`, its screen configurations and the
/// [OmniBlogDependentAppAttributes] that carries the WebRTC settings.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return KataglyphisAppShell<OmniBootstrapData>(
      loadBootstrapData: loadAppSettings,
      appLocalizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
      ],
      buildBinding:
          (OmniBootstrapData data, KataglyphisAppShellRuntime runtime) {
            final (
              appSettings,
              userSettings,
              blogConfigs,
              twoCentsConfigs,
              webrtcSettings,
            ) = data;

            final JotrockenmitLockenScreenConfigurations screenConfigurations =
                JotrockenmitLockenScreenConfigurations.fromBlogAndDataConfigs(
                  blogPageConfigs: blogConfigs,
                  twoCentsConfigs: twoCentsConfigs,
                );

            return KataglyphisAppShellBinding(
              appAttributes: runtime.buildAppAttributes(
                footerConfig: DefaultFooterConfig(),
                homeConfig: DefaultHomeConfig(),
                appSettings: appSettings,
                userSettings: userSettings,
                screenConfigurations: screenConfigurations,
              ),
              routesCreator: JotrockenMitLockenRoutes(
                blogDependentAppAttributes: OmniBlogDependentAppAttributes(
                  blogDependentScreenConfigurations: screenConfigurations,
                  twoCentsConfigs: twoCentsConfigs,
                  blockSettings: blogConfigs,
                  webrtcSettings: webrtcSettings,
                ),
              ),
            );
          },
    );
  }
}
