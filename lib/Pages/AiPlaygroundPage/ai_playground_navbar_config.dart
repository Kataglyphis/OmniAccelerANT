import 'package:flutter/material.dart';
import 'package:anthology/Pages/navbar_page_config.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

class AiPlaygroundNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.smart_toy_outlined),
      label: AppLocalizations.of(context)!.aiPlaygroundNav,
      selectedIcon: const Icon(Icons.smart_toy),
    );
  }

  @override
  String getRoutingName() {
    return '/aiPlayground';
  }
}
