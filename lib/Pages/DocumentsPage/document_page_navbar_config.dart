import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Pages/navbar_page_config.dart';

class DocumentPageNavBarConfig extends NavBarPageConfig {
  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: const Icon(Icons.description_outlined),
      label: AppLocalizations.of(context)!.documents,
      selectedIcon: const Icon(Icons.description),
    );
  }

  @override
  String getRoutingName() {
    return '/documents';
  }
}
