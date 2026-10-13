import 'package:flutter/material.dart';
import 'package:anthology/Pages/navbar_page_config.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

class CameraSettingsNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.tune_outlined),
      label: AppLocalizations.of(context)!.cameraSettingsNav,
      selectedIcon: const Icon(Icons.tune),
    );
  }

  @override
  String getRoutingName() {
    return '/cameraSettings';
  }
}
