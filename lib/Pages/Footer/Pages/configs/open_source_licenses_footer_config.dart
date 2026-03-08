import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer_page_config.dart';

class OpenSourceLicensesFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return (Localizations.localeOf(context) == const Locale('de'))
        ? 'Open-Source-Lizenzen'
        : 'Open Source Licenses';
  }

  @override
  String getRoutingName() {
    return "/openSourceLicenses";
  }

  @override
  String getFilePathDe() {
    return 'assets/documents/footer/openSourceLicensesDe.md';
  }

  @override
  String getFilePathEn() {
    return 'assets/documents/footer/openSourceLicensesEn.md';
  }
}
