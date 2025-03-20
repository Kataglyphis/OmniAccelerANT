import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/navbar_page_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class LandingPageNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.house_outlined),
      label: AppLocalizations.of(context)!.homepage,
      selectedIcon: const Icon(Icons.house),
    );
  }

  @override
  String getRoutingName() {
    return "/landingPage";
  }
}
