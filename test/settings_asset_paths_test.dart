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

/// Every `filePath` and `docsDesc[].baseDir`+`title` in a settings file, repo-relative.
List<String> _assetPathsIn(Object? node) {
  final List<String> found = <String>[];

  void walk(Object? value) {
    if (value is List) {
      for (final Object? item in value) {
        walk(item);
      }
    } else if (value is Map) {
      final Object? filePath = value['filePath'];
      if (filePath is String && filePath.startsWith('assets/')) {
        found.add(filePath);
      }
      // docsDesc entries name a directory and a filename separately.
      final Object? baseDir = value['baseDir'];
      final Object? title = value['title'];
      if (baseDir is String &&
          title is String &&
          baseDir.startsWith('assets/')) {
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

void main() {
  final Directory root = _repoRoot();

  const List<String> settingsFiles = <String>[
    'assets/settings/blog_settings.json',
    'assets/settings/my_two_cents_settings.json',
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

        final List<String> missing = declared
            .where((String p) => !File('${root.path}/$p').existsSync())
            .where((String p) => !_isKnownMissing(p))
            .toList();

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

  group('present documents are actually bundled', () {
    test('pubspec.yaml lists every assets/documents subdirectory', () {
      // An unlisted directory ships nothing, and rootBundle fails as if the file were missing.
      final String pubspec = File(
        '${root.path}/pubspec.yaml',
      ).readAsStringSync();
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
