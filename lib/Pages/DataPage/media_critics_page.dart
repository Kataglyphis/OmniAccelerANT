import 'package:flutter/material.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/Pages/markdown_content_page.dart';
import 'package:anthology/my_two_cents_config.dart';

/// A media review rendered by [MarkdownContentPage], with its appendix files.
class MediaCriticsPage extends StatelessWidget {
  /// The application-wide attributes for theming and layout.
  final AppAttributes appAttributes;

  /// The footer widget to display at the bottom of the page.
  final Footer footer;

  /// The configuration for this media critics page, including file paths and metadata.
  final MyTwoCentsConfig mediaCriticsPageConfig;

  const MediaCriticsPage({
    super.key,
    required this.appAttributes,
    required this.footer,
    required this.mediaCriticsPageConfig,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownContentPage(
      appAttributes: appAttributes,
      footer: footer,
      config: mediaCriticsPageConfig,
    );
  }
}
