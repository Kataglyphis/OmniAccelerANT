import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/Pages/LandingPage/landing_page.dart';
import 'package:anthology/Pages/navbar_page_config.dart';
import 'package:anthology/app_attributes.dart';
import 'package:flutter/material.dart';
import 'package:omni_accelerant/Pages/AboutMePage/about_me_page.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_page.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings_page.dart';
import 'package:omni_accelerant/Pages/DevicePage/device_page.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_page.dart';
import 'package:omni_accelerant/blog_dependent_app_attributes.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

/// Builds one navigation page from the shared footer and the app's attributes.
typedef AppPageBuilder = Widget Function(
  Footer footer,
  AppAttributes appAttributes,
  OmniBlogDependentAppAttributes blogDependentAppAttributes,
);

/// One navigation-rail page: its route, rail entry and widget.
class AppPage extends NavBarPageConfig {
  AppPage({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.build,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String Function(AppLocalizations l10n) label;
  final AppPageBuilder build;

  @override
  NavigationDestination getNavigationDestination(BuildContext context) {
    return NavigationDestination(
      tooltip: '',
      icon: Icon(icon),
      label: label(AppLocalizations.of(context)!),
      selectedIcon: Icon(selectedIcon),
    );
  }

  @override
  String getRoutingName() => route;
}

/// The navigation-rail pages in rail order; routing, the layout test and the web check read this table.
final List<AppPage> appPages = <AppPage>[
  AppPage(
    route: '/stream',
    icon: Icons.camera_enhance_outlined,
    selectedIcon: Icons.camera_enhance,
    label: (l10n) => l10n.stream,
    build: (footer, app, blog) => StreamPage(
      footer: footer,
      appAttributes: app,
      webrtcSettings: blog.webrtcSettings,
    ),
  ),
  AppPage(
    route: '/cameraSettings',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    label: (l10n) => l10n.cameraSettingsNav,
    build: (footer, app, blog) =>
        CameraSettingsPage(footer: footer, appAttributes: app),
  ),
  AppPage(
    route: '/device',
    icon: Icons.usb_outlined,
    selectedIcon: Icons.usb,
    label: (l10n) => l10n.deviceNav,
    build: (footer, app, blog) =>
        DevicePage(footer: footer, appAttributes: app),
  ),
  AppPage(
    route: '/aiPlayground',
    icon: Icons.smart_toy_outlined,
    selectedIcon: Icons.smart_toy,
    label: (l10n) => l10n.aiPlaygroundNav,
    build: (footer, app, blog) =>
        AiPlaygroundPage(footer: footer, appAttributes: app),
  ),
  AppPage(
    route: '/landingPage',
    icon: Icons.house_outlined,
    selectedIcon: Icons.house,
    label: (l10n) => l10n.homepage,
    build: (footer, app, blog) => LandingPage(
      footer: footer,
      appAttributes: app,
      blogDependentAppAttributes: blog,
    ),
  ),
  AppPage(
    route: '/aboutMe',
    icon: Icons.person_outlined,
    selectedIcon: Icons.person,
    label: (l10n) => l10n.aboutme,
    build: (footer, app, blog) =>
        AboutMePage(footer: footer, appAttributes: app),
  ),
];
