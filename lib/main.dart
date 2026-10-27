// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:anthology/Boot/boot_overlay.dart';
import 'package:anthology/Pages/Footer/default_footer_config.dart';
import 'package:anthology/Pages/Home/default_home_config.dart';
import 'package:anthology/app_settings.dart';
import 'package:anthology/app_shell.dart';
import 'package:anthology/blog_page_config.dart';
import 'package:anthology/settings_loader.dart';
import 'package:anthology/user_settings.dart';

import 'package:omni_accelerant/Pages/omni_screen_configurations.dart';
import 'package:omni_accelerant/Routing/omni_router.dart';
import 'package:omni_accelerant/blog_dependent_app_attributes.dart';
import 'package:omni_accelerant/fallback_font_licenses.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';
import 'package:omni_accelerant/src/boot/rust_core.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';
import 'package:omni_accelerant/third_party_licenses.dart';

/// Everything read off disk before the first frame; [WebRTCSettings] makes it Omni's own type.
typedef OmniBootstrapData = (
  AppSettings,
  UserSettings,
  List<BlogPageConfig>,
  WebRTCSettings,
);

const String userSettingsFilePath =
    "assets/settings/user_settings/global_user_settings.json";
const String appSettingsFilePath = "assets/settings/app_settings.json";
const String blogSettingsFilePath = "assets/settings/blog_settings.json";
const String webrtcSettingsFilePath = "assets/settings/webrtc_settings.json";

/// Loads all settings files in parallel; a bad or missing file is logged and rethrown.
Future<OmniBootstrapData> loadAppSettings([SettingsLoader? loader]) async {
  final SettingsLoader settings = loader ?? SettingsLoader();
  final List<Object> results = await Future.wait<Object>([
    settings.loadShared(
      userSettingsPath: userSettingsFilePath,
      appSettingsPath: appSettingsFilePath,
      blogSettingsPath: blogSettingsFilePath,
    ),
    settings.load(
      webrtcSettingsFilePath,
      (json) => WebRTCSettings.fromJsonFile(json as Map<String, dynamic>),
    ),
  ]);
  final (appSettings, userSettings, blogConfigs) = results[0] as SharedSettings;
  return (appSettings, userSettings, blogConfigs, results[1] as WebRTCSettings);
}

Future<void> main() async {
  // The timeout matters: without web/pkg/ frb's loader never completes, and the page would stay on its spinner.
  await loadRustCore(
    () => RustLib.init().timeout(const Duration(seconds: 20)),
    // Firefox and Safari refuse the core's shared wasm memory without COOP/COEP, and the web streams without it.
    optional: kIsWeb,
  );
  dismissBootOverlay();
  registerFallbackFontLicenses();
  registerThirdPartyLicenses();
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
            final (appSettings, userSettings, blogConfigs, webrtcSettings) =
                data;

            final OmniScreenConfigurations screenConfigurations =
                OmniScreenConfigurations(blogPageConfigs: blogConfigs);

            return KataglyphisAppShellBinding(
              appAttributes: runtime.buildAppAttributes(
                footerConfig: DefaultFooterConfig(),
                homeConfig: DefaultHomeConfig(),
                appSettings: appSettings,
                userSettings: userSettings,
                screenConfigurations: screenConfigurations,
              ),
              routesCreator: OmniRoutes(
                blogDependentAppAttributes: OmniBlogDependentAppAttributes(
                  blogDependentScreenConfigurations: screenConfigurations,
                  blockSettings: blogConfigs,
                  webrtcSettings: webrtcSettings,
                ),
              ),
            );
          },
    );
  }
}
