import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_page_config.dart';

class PrivacyPolicyFooterConfig extends FooterPageConfig {
  @override
  String getHeading(BuildContext context) {
    return AnthologyLocalizations.of(context)!.privacyPolicy;
  }

  @override
  String getRoutingName() {
    return "/privacyPolicy";
  }

  @override
  String getFilePathDe() {
    return 'packages/anthology/assets/documents/footer/privacyPolicyDe.md';
  }

  @override
  String getFilePathEn() {
    return 'packages/anthology/assets/documents/footer/privacyPolicyEn.md';
  }
}
