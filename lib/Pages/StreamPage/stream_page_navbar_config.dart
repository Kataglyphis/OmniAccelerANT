import 'package:flutter/material.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:anthology/Pages/navbar_page_config.dart';

class StreamPageNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.camera_enhance_outlined),
      label: AppLocalizations.of(context)!.stream,
      selectedIcon: const Icon(Icons.camera_enhance),
    );
  }

  @override
  String getRoutingName() {
    return '/stream';
  }
}
