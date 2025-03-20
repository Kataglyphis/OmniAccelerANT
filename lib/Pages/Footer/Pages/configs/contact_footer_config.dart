import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer_page_config.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ContactFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AppLocalizations.of(context)!.contact;
  }

  @override
  String getRoutingName() {
    return "/contact";
  }

  @override
  String getFilePathDe() {
    return 'assets/documents/footer/contactDe.md';
  }

  @override
  String getFilePathEn() {
    return 'assets/documents/footer/contactEn.md';
  }
}
