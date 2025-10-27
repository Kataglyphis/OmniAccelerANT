import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/Pages/navbar_page_config.dart';

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
