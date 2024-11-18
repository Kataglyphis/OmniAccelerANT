import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Pages/navbar_page_config.dart';

class DataPageNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.folder_open_outlined),
      label: AppLocalizations.of(context)!.data,
      selectedIcon: const Icon(Icons.folder_open),
    );
  }

  @override
  String getRoutingName() {
    return '/data';
  }
}
