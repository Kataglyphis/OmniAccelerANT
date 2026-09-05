import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer_config.dart';
import 'package:anthology/Url/external_link_config.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

class JoTrockenMitLockenFooterConfig extends FooterConfig {
  @override
  List<ExternalLinkConfig> getExternalLinks(BuildContext context) {
    return [
      ExternalLinkConfig(host: 'johannes-heinle.de', path: ''),
      ExternalLinkConfig(host: 'dom-wuest.de', path: ''),
    ];
  }

  @override
  String getExternalLinksTitle(BuildContext context) {
    return AppLocalizations.of(context)!.externalLinks;
  }

  @override
  String getLiabilityText(BuildContext context) {
    return "${AppLocalizations.of(context)!.disclaimer}\n${AppLocalizations.of(context)!.copyright}";
  }
}
