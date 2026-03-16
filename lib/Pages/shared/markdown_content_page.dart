import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file.dart';
import 'package:jotrockenmitlockenrepo/Media/Files/file_table.dart';
import 'package:jotrockenmitlockenrepo/Media/Markdown/markdown_page.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';

/// Configuration interface for pages that display markdown content with appendix files.
///
/// This interface abstracts the common configuration needed by both [BlogPageConfig]
/// and [MyTwoCentsConfig], enabling code reuse through [MarkdownContentPage].
abstract class MarkdownContentConfig {
  /// The path to the markdown file to display.
  String get filePath;

  /// The directory containing images referenced in the markdown.
  String get imageDir;

  /// List of appendix documents with their metadata.
  ///
  /// Each map should contain:
  /// - 'baseDir': The base directory for the file
  /// - 'title': The display title
  /// - 'additionalInfo': Additional information about the file
  List<Map<String, String>> get docsDesc;
}

/// A reusable widget for displaying markdown content with an appendix file table.
///
/// This widget consolidates the common functionality between [BlogPage] and
/// [MediaCriticsPage], reducing code duplication and improving maintainability.
///
/// Example usage:
/// ```dart
/// MarkdownContentPage(
///   appAttributes: appAttributes,
///   footer: footer,
///   config: blogPageConfig,
///   appendixTitle: 'References',
/// )
/// ```
class MarkdownContentPage extends StatelessWidget {
  /// The application-wide attributes for theming and layout.
  final AppAttributes appAttributes;

  /// The footer widget to display at the bottom of the page.
  final Footer footer;

  /// The configuration containing markdown file path and appendix documents.
  final MarkdownContentConfig config;

  /// The title displayed above the appendix file table.
  ///
  /// Defaults to 'Appendix' if not specified.
  final String appendixTitle;

  const MarkdownContentPage({
    super.key,
    required this.appAttributes,
    required this.footer,
    required this.config,
    this.appendixTitle = 'Appendix',
  });

  @override
  Widget build(BuildContext context) {
    final docs = config.docsDesc
        .map(
          (fileConfig) => File(
            baseDir: fileConfig['baseDir'] ?? '',
            title: fileConfig['title'] ?? '',
            additionalInfo: fileConfig['additionalInfo'] ?? '',
          ),
        )
        .toList();

    return SinglePage(
      footer: footer,
      appAttributes: appAttributes,
      showMediumSizeLayout: appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: appAttributes.showLargeSizeLayout,
      children: [
        MarkdownFilePage(
          currentLocale: Localizations.localeOf(context),
          filePathDe: '',
          filePathEn: config.filePath,
          imageDirectory: config.imageDir,
          useLightMode: appAttributes.useLightMode,
        ),
        FileTable(title: appendixTitle, docs: docs),
      ],
    );
  }
}
