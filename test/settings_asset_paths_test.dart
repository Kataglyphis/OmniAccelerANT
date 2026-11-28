// Declared assets must exist AND be bundled: pubspec's `assets/documents/` entry is not recursive.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Document trees the settings reference but the repo lacks; a ratchet, so shrink it, never grow it.
const Set<String> _knownMissing = <String>{};

Directory _repoRoot() {
  Directory dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final Directory parent = dir.parent;
    if (parent.path == dir.path) fail('could not find the repo root');
    dir = parent;
  }
  return dir;
}

bool _isKnownMissing(String path) =>
    _knownMissing.any((String prefix) => path.startsWith(prefix));

/// An asset key the settings may name: the app's own `assets/`, or a dependency's `packages/<name>/`.
bool _isAssetKey(String path) =>
    path.startsWith('assets/') || path.startsWith('packages/');

/// Every `filePath` and `docsDesc[].baseDir`+`title` in a settings file, as asset keys.
List<String> _assetPathsIn(Object? node) {
  final List<String> found = <String>[];

  void walk(Object? value) {
    if (value is List) {
      for (final Object? item in value) {
        walk(item);
      }
    } else if (value is Map) {
      final Object? filePath = value['filePath'];
      if (filePath is String && _isAssetKey(filePath)) {
        found.add(filePath);
      }
      // docsDesc entries name a directory and a filename separately.
      final Object? baseDir = value['baseDir'];
      final Object? title = value['title'];
      if (baseDir is String && title is String && _isAssetKey(baseDir)) {
        found.add('$baseDir$title');
      }
      for (final Object? child in value.values) {
        walk(child);
      }
    }
  }

  walk(node);
  return found;
}

/// Package roots by name, from the package config `flutter test` resolves the app against.
Map<String, Directory> _packageRoots(Directory root) {
  final File config = File('${root.path}/.dart_tool/package_config.json');
  final Object? decoded = json.decode(config.readAsStringSync());
  final Object? packages = (decoded! as Map<String, Object?>)['packages'];
  final Map<String, Directory> roots = <String, Directory>{};
  for (final Object? entry in packages! as List<Object?>) {
    final Map<String, Object?> package = entry! as Map<String, Object?>;
    // A path dependency's rootUri is relative to .dart_tool/, not to the repo root.
    final Uri rootUri = config.uri.resolve(package['rootUri']! as String);
    roots[package['name']! as String] = Directory.fromUri(rootUri);
  }
  return roots;
}

/// The file behind an asset key; null for a package the app does not resolve.
File? _assetFile(Directory root, Map<String, Directory> packages, String key) {
  if (!key.startsWith('packages/')) return File('${root.path}/$key');
  final List<String> parts = key.split('/');
  final Directory? package = packages[parts[1]];
  if (package == null || parts.length < 3) return null;
  return File('${package.path}/${parts.sublist(2).join('/')}');
}

/// The declared keys with no file behind them, the known gaps aside.
List<String> _missingAssets(
  Directory root,
  Map<String, Directory> packages,
  List<String> declared,
) {
  final List<String> missing = <String>[];
  for (final String key in declared) {
    final File? file = _assetFile(root, packages, key);
    if ((file == null || !file.existsSync()) && !_isKnownMissing(key)) {
      missing.add(key);
    }
  }
  return missing;
}

void main() {
  final Directory root = _repoRoot();

  const List<String> settingsFiles = <String>[
    'assets/settings/blog_settings.json',
  ];

  group('every declared asset exists on disk', () {
    for (final String settings in settingsFiles) {
      test(settings, () {
        final File file = File('${root.path}/$settings');
        expect(file.existsSync(), isTrue, reason: '$settings is missing');

        final Object? decoded = json.decode(file.readAsStringSync());
        // No entries declare nothing; entries that yield no path mean the walker missed the schema.
        if (decoded is List && decoded.isEmpty) return;
        final List<String> declared = _assetPathsIn(decoded);
        expect(
          declared,
          isNotEmpty,
          reason:
              'parsed no asset paths out of $settings — the schema changed and '
              'this test is now checking nothing. Fix the walker.',
        );

        final Map<String, Directory> packages = _packageRoots(root);
        final List<String> missing = _missingAssets(root, packages, declared);

        expect(
          missing,
          isEmpty,
          reason:
              'declared in $settings but absent from the repo:\n'
              '  ${missing.join('\n  ')}\n'
              'Either ship the file or remove the entry. If it is a known gap, '
              'add its directory to _knownMissing WITH a reason — but prefer '
              'fixing it: every entry here is a broken link on the live site.',
        );
      });
    }
  });

  group('the ratchet stays honest', () {
    test('nothing in _knownMissing has quietly appeared', () {
      // A tree that comes back must leave the allowance.
      final List<String> resurrected = _knownMissing
          .where((String dir) => Directory('${root.path}/$dir').existsSync())
          .toList();
      expect(
        resurrected,
        isEmpty,
        reason:
            'these exist again and must be removed from _knownMissing:\n'
            '  ${resurrected.join('\n  ')}',
      );
    });
  });

  group('the walker reads package assets', () {
    test('every filePath in blog_settings.json is collected', () {
      final String blog = '${root.path}/assets/settings/blog_settings.json';
      final Object? decoded = json.decode(File(blog).readAsStringSync());
      final List<String> filePaths = <String>[];
      for (final Object? entry in decoded! as List<Object?>) {
        final Object? path = (entry! as Map<String, Object?>)['filePath'];
        if (path is String) filePaths.add(path);
      }
      expect(filePaths, isNotEmpty);
      expect(_assetPathsIn(decoded), containsAll(filePaths));
    });

    test('a missing package asset is named, a present one is not', () {
      final Directory fixture = Directory.systemTemp.createTempSync('assets_');
      addTearDown(() => fixture.deleteSync(recursive: true));
      final String base = fixture.path;
      File('$base/vendor/shared/assets/present.md').createSync(recursive: true);
      Directory('$base/.dart_tool').createSync();
      final String config = json.encode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{'name': 'shared', 'rootUri': '../vendor/shared'},
        ],
      });
      File('$base/.dart_tool/package_config.json').writeAsStringSync(config);
      final List<String> declared = _assetPathsIn(<Object?>[
        <String, Object?>{'filePath': 'packages/shared/assets/present.md'},
        <String, Object?>{'filePath': 'packages/shared/assets/missing.md'},
        <String, Object?>{'filePath': 'packages/unknown/assets/present.md'},
      ]);
      final Map<String, Directory> packages = _packageRoots(fixture);
      expect(_missingAssets(fixture, packages, declared), <String>[
        'packages/shared/assets/missing.md',
        'packages/unknown/assets/present.md',
      ]);
    });
  });

  group('present documents are actually bundled', () {
    test('pubspec.yaml lists every assets/documents subdirectory', () {
      // An unlisted directory ships nothing, and rootBundle fails as if the file were missing.
      final String pubspec = File('${root.path}/pubspec.yaml')
          .readAsStringSync();
      final Directory documents = Directory('${root.path}/assets/documents');
      if (!documents.existsSync()) return;

      final List<String> unlisted = documents
          .listSync()
          .whereType<Directory>()
          .map(
            (Directory d) =>
                'assets/documents/${d.uri.pathSegments.where((String s) => s.isNotEmpty).last}/',
          )
          .where((String rel) => !pubspec.contains(rel))
          .toList();

      expect(
        unlisted,
        isEmpty,
        reason:
            'these directories exist but pubspec.yaml does not list them, so '
            'Flutter bundles nothing from them:\n  ${unlisted.join('\n  ')}\n'
            "pubspec's `assets/documents/` entry is not recursive.",
      );
    });
  });
}
