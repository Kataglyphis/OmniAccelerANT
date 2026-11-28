import 'dart:convert';

import 'package:flutter/services.dart';

/// The inventory `scripts/licenses/web-license-inventory.py` writes into the built web app; no pubspec asset, so a web bundle fetches it.
const String webLicenseIndexKey = 'web-licenses/index.json';

/// The groups in the order the generator sorts them.
const List<String> webLicenseGroups = <String>[
  'app',
  'engine',
  'dart',
  'wasm',
  'cargo',
  'ort',
  'models',
  'fonts',
  'javascript',
];

/// One license text of a component, stored under its SHA-256 in one of the inventory's text chunks.
class WebLicenseText {
  const WebLicenseText({
    required this.title,
    required this.sha256,
    required this.file,
  });

  final String title;
  final String sha256;

  /// The chunk that holds the text, beside the index.
  final String file;
}

/// A component of the web build: what it is, its license and the shipped files it covers.
class WebLicenseComponent {
  const WebLicenseComponent({
    required this.group,
    required this.id,
    required this.name,
    required this.files,
    required this.texts,
    this.version,
    this.license,
    this.source,
    this.includes = const <String>[],
  });

  factory WebLicenseComponent.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        ((json[key] as List<dynamic>?) ?? const <dynamic>[]).cast<String>();
    return WebLicenseComponent(
      group: json['group'] as String,
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String?,
      license: json['license'] as String?,
      source: json['source'] as String?,
      files: strings('files'),
      includes: strings('includes'),
      texts: (json['texts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (text) => WebLicenseText(
              title: text['title'] as String,
              sha256: text['sha256'] as String,
              file: text['file'] as String,
            ),
          )
          .toList(),
    );
  }

  final String group;
  final String id;
  final String name;
  final String? version;
  final String? license;
  final String? source;
  final List<String> files;
  final List<String> includes;
  final List<WebLicenseText> texts;

  /// The name with its version, as the page titles it.
  String get title => version == null ? name : '$name $version';
}

/// The whole inventory: how many files the build ships and the components covering them.
class WebLicenseInventory {
  const WebLicenseInventory({
    required this.fileCount,
    required this.components,
  });

  factory WebLicenseInventory.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw FormatException('unknown inventory schema ${json['schema']}');
    }
    return WebLicenseInventory(
      fileCount: json['file_count'] as int,
      components: (json['components'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(WebLicenseComponent.fromJson)
          .toList(),
    );
  }

  final int fileCount;
  final List<WebLicenseComponent> components;

  /// The components of each known group, in [webLicenseGroups] order, empty groups left out.
  List<(String, List<WebLicenseComponent>)> get groups =>
      <(String, List<WebLicenseComponent>)>[
        for (final group in webLicenseGroups)
          if (components.any((component) => component.group == group))
            (
              group,
              components
                  .where((component) => component.group == group)
                  .toList(),
            ),
      ];
}

/// Reads the inventory from [bundle]; on the web this is a fetch below the app's `assets/`.
Future<WebLicenseInventory> loadWebLicenseInventory(AssetBundle bundle) async {
  final Object? json = jsonDecode(
    await bundle.loadString(webLicenseIndexKey, cache: false),
  );
  return WebLicenseInventory.fromJson(json! as Map<String, dynamic>);
}

/// Reads license texts from [bundle], decoding each chunk once however many texts it holds.
class WebLicenseTexts {
  WebLicenseTexts(this.bundle);

  final AssetBundle bundle;
  final Map<String, Future<Map<String, dynamic>>> _chunks =
      <String, Future<Map<String, dynamic>>>{};

  Future<String> load(WebLicenseText text) async {
    final Map<String, dynamic> chunk = await _chunks.putIfAbsent(
      text.file,
      () async =>
          jsonDecode(await bundle.loadString('web-licenses/${text.file}'))
              as Map<String, dynamic>,
    );
    final Object? found = chunk[text.sha256];
    if (found is! String) {
      throw FormatException('${text.file} holds no text ${text.sha256}');
    }
    return found;
  }
}
