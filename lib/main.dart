// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
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
import 'package:omni_accelerant/src/boot/boot_overlay.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

/// Everything read off disk before the first frame; [WebRTCSettings] makes it Omni's own type.
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

/// Loads all settings files in parallel; throws [FormatException] on malformed JSON.
Future<OmniBootstrapData> loadAppSettings() async {
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
  // The timeout matters: without web/pkg/ frb's loader never completes, so a bare catch would hang on the spinner.
  try {
    await RustLib.init().timeout(const Duration(seconds: 20));
  } catch (error, stackTrace) {
    showBootFailure(error, stackTrace);
    rethrow;
  }
  dismissBootOverlay();
  runApp(const App());
}

/// OmniAccelerANT's binding of the shared [KataglyphisAppShell].
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
