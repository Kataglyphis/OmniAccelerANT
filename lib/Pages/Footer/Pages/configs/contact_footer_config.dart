import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';

class ContactFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AnthologyLocalizations.of(context)!.contact;
  }

  @override
  String getRoutingName() {
    return "/contact";
  }

  @override
  String getFilePathDe() {
    return 'packages/anthology/assets/documents/footer/contactDe.md';
  }

  @override
  String getFilePathEn() {
    return 'packages/anthology/assets/documents/footer/contactEn.md';
  }
}
