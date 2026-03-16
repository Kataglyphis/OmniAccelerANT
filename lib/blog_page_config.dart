import 'package:jotrockenmitlockenrepo/Pages/stateful_branch_info_provider.dart';
import 'package:kataglyphis_inference_engine/Pages/shared/markdown_content_page.dart';

/// Alignment options for landing page entries.
enum LandingPageAlignment { left, right }

/// Configuration for a blog page loaded from JSON settings.
///
/// This class holds all metadata and content paths needed to render a blog post,
/// including the markdown file path, image directory, and appendix documents.
///
/// Implements [MarkdownContentConfig] to enable use with [MarkdownContentPage].
class BlogPageConfig extends StatefulBranchInfoProvider
    implements MarkdownContentConfig {
  /// Creates a [BlogPageConfig] from a JSON map.
  ///
  /// Throws [TypeError] if required fields are missing or have wrong types.
  /// Consider using [BlogPageConfig.tryFromJsonFile] for safer parsing.
  BlogPageConfig.fromJsonFile(Map<String, dynamic> jsonFile)
    : routingName = _requireString(jsonFile, 'routingName'),
      shortDescriptionEN = _requireString(jsonFile, 'shortDescriptionEN'),
      shortDescriptionDE = _requireString(jsonFile, 'shortDescriptionDE'),
      filePath = _requireString(jsonFile, 'filePath'),
      imageDir = _requireString(jsonFile, 'imageDir'),
      githubRepo = _requireString(jsonFile, 'githubRepo'),
      landingPageAlignment = _requireString(jsonFile, 'landingPageAlignment'),
      landingPageEntryImagePath = _requireString(
        jsonFile,
        'landingPageEntryImagePath',
      ),
      landingPageEntryImageCaptioning =
          jsonFile['landingPageEntryImageCaptioning'] as String?,
      lastModified = _requireString(jsonFile, 'lastModified'),
      fileTitle = _requireString(jsonFile, 'fileTitle'),
      fileAdditionalInfo = _requireString(jsonFile, 'fileAdditionalInfo'),
      fileBaseDir = _requireString(jsonFile, 'fileBaseDir') {
    _parseDocsDesc(jsonFile['docsDesc']);
  }

  /// Safely extracts a required string field from JSON.
  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      throw FormatException('Missing required field: $key');
    }
    if (value is! String) {
      throw FormatException(
        'Field "$key" must be a String, got ${value.runtimeType}',
      );
    }
    return value;
  }

  /// Parses the docsDesc array from JSON with validation.
  void _parseDocsDesc(dynamic docsDescJson) {
    if (docsDescJson == null) return;
    if (docsDescJson is! List) {
      throw FormatException('docsDesc must be a List');
    }
    for (var element in docsDescJson) {
      if (element is! Map) continue;
      docsDesc.add({
        'baseDir': element['baseDir']?.toString() ?? '',
        'title': element['title']?.toString() ?? '',
        'additionalInfo': element['additionalInfo']?.toString() ?? '',
      });
    }
  }

  /// The URL-friendly name used for routing.
  final String routingName;

  /// Short description in English for previews and SEO.
  final String shortDescriptionEN;

  /// Short description in German for previews and SEO.
  final String shortDescriptionDE;

  /// Path to the markdown content file.
  @override
  final String filePath;

  /// Directory containing images referenced in the markdown.
  @override
  final String imageDir;

  /// GitHub repository URL for the project.
  final String githubRepo;

  /// Alignment of the entry on the landing page ('left' or 'right').
  final String landingPageAlignment;

  /// Path to the image displayed on the landing page.
  final String landingPageEntryImagePath;

  /// Optional caption for the landing page image.
  final String? landingPageEntryImageCaptioning;

  /// Last modification date string.
  final String lastModified;

  /// Title of the associated file.
  final String fileTitle;

  /// Additional information about the file.
  final String fileAdditionalInfo;

  /// Base directory for file downloads.
  final String fileBaseDir;

  /// List of appendix document configurations.
  @override
  final List<Map<String, String>> docsDesc = [];

  @override
  String getRoutingName() => routingName;
}
