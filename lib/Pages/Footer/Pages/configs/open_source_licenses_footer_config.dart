import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';
import 'package:anthology/l10n/anthology_localizations.dart';

class OpenSourceLicensesFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    // Was a hand-rolled localeOf(context) ternary, i.e. a second private copy of
    // a string the shared catalogue already owns - and one that would have
    // served English to any third locale this app grows into.
    return AnthologyLocalizations.of(context)!.openSourceLicenses;
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
