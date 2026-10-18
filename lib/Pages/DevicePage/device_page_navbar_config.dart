import 'package:flutter/material.dart';
import 'package:anthology/Pages/navbar_page_config.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

class DeviceNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.usb_outlined),
      label: AppLocalizations.of(context)!.deviceNav,
      selectedIcon: const Icon(Icons.usb),
    );
  }

  @override
  String getRoutingName() {
    return '/device';
  }
}
