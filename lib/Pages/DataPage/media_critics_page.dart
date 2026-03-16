import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:kataglyphis_inference_engine/Pages/shared/markdown_content_page.dart';
import 'package:kataglyphis_inference_engine/my_two_cents_config.dart';

/// A page that displays media critique/review content with markdown rendering.
///
/// This widget uses [MarkdownContentPage] to render the review markdown
/// and display associated appendix documents in a file table.
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
      appendixTitle: 'Appendix',
    );
  }
}
