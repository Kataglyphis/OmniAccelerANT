import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/navbar_page_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AboutMePageNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.person_outlined),
      label: AppLocalizations.of(context)!.aboutme,
      selectedIcon: const Icon(Icons.person),
    );
  }

  @override
  String getRoutingName() {
    return '/aboutMe';
  }
}
