import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:kataglyphis_inference_engine/Pages/shared/markdown_content_page.dart';
import 'package:kataglyphis_inference_engine/blog_page_config.dart';

/// A page that displays blog content with markdown rendering and appendix files.
///
/// This widget uses [MarkdownContentPage] to render the blog post markdown
/// and display associated appendix documents in a file table.
class BlogPage extends StatelessWidget {
  /// The application-wide attributes for theming and layout.
  final AppAttributes appAttributes;

  /// The footer widget to display at the bottom of the page.
  final Footer footer;

  /// The configuration for this blog page, including file paths and metadata.
  final BlogPageConfig blogPageConfig;

  const BlogPage({
    super.key,
    required this.appAttributes,
    required this.footer,
    required this.blogPageConfig,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownContentPage(
      appAttributes: appAttributes,
      footer: footer,
      config: blogPageConfig,
      appendixTitle: 'Appendix',
    );
  }
}
