import 'package:jotrockenmitlockenrepo/Pages/stateful_branch_info_provider.dart';
import 'package:kataglyphis_inference_engine/Pages/shared/markdown_content_page.dart';

/// Configuration for a "My Two Cents" / media critics page loaded from JSON.
///
/// This class holds metadata and content paths for opinion/review pages.
/// Implements [MarkdownContentConfig] to enable use with [MarkdownContentPage].
class MyTwoCentsConfig extends StatefulBranchInfoProvider
    implements MarkdownContentConfig {
  /// Creates a [MyTwoCentsConfig] from a JSON map.
  ///
  /// Throws [FormatException] if required fields are missing or have wrong types.
  MyTwoCentsConfig.fromJsonFile(Map<String, dynamic> jsonFile)
    : routingName = _requireString(jsonFile, 'routingName'),
      filePath = _requireString(jsonFile, 'filePath'),
      imageDir = _requireString(jsonFile, 'imageDir'),
      mediaTitle = _requireString(jsonFile, 'mediaTitle'),
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

  /// Path to the markdown content file.
  @override
  final String filePath;

  /// Directory containing images referenced in the markdown.
  @override
  final String imageDir;

  /// Title of the media being reviewed/discussed.
  final String mediaTitle;

  /// Base directory for file downloads.
  final String fileBaseDir;

  /// List of appendix document configurations.
  @override
  final List<Map<String, String>> docsDesc = [];

  @override
  String getRoutingName() => routingName;
}
