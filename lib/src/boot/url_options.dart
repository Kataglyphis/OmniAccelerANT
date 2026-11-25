import 'dart:ui' show Locale;

import 'package:omni_accelerant/app_pages.dart';

/// `?lang=en` on the page's address, so a link or a screenshot can ask for one language.
Locale? localeFromUrl(Uri url) {
  final String? lang = url.queryParameters['lang'];
  if (lang == null || !RegExp(r'^[A-Za-z]{2,3}$').hasMatch(lang)) {
    return null;
  }
  return Locale(lang.toLowerCase());
}

/// The rail page to open on when the address names none; the hosted showcase sets it, since its static host has no camera.
const String hostedStartRoute = String.fromEnvironment('OMNI_START_ROUTE');

/// [route]'s index among the rail pages, which come first in the router's page list; [fallback] for an unknown or empty route.
int startPageIndex(String route, int fallback) {
  final int index = appPages.indexWhere((AppPage page) => page.route == route);
  return index >= 0 ? index : fallback;
}
