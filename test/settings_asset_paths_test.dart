// Asserts that every asset path the shipped settings JSON declares actually
// exists on disk, and that everything under assets/documents/ is reachable
// through pubspec.yaml's asset list.
//
// Two distinct failures hide here, and only the first is obvious:
//   1. the file is not on disk — the page renders a failed markdown load;
//   2. the file IS on disk but is not bundled, because pubspec.yaml's
//      `assets/documents/` entry is NON-RECURSIVE: Flutter bundles the files
//      directly in a listed directory, not its subdirectories. So restoring a
//      missing document is two steps, and doing only the first looks identical
//      to doing nothing.
// This test separates them, using dart:io rather than rootBundle so it can tell
// "absent" from "present but unbundled" at all.
//
// It is a RATCHET, like the *.allow files at the repo root: `_knownMissing`
// records what is broken TODAY so the suite is green, and the test fails if
// anything NEW breaks or if a known-missing entry is quietly resurrected in the
// settings without being restored on disk. Shrink the set; never grow it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Document trees referenced by the settings but absent from the repo.
///
/// Recorded 2026-09-16. `books/` and `games/` hold the markdown for the
/// /books/* and /games/* routes; equivalents exist under `dummy_assets/`, so
/// restoring them is a content decision, not a recovery problem. Until then
/// those routes render a failed load.
///
/// `cv/` is deliberately NOT here: the owner decided on 2026-09-16 not to ship
/// the CV PDFs, and the five `docsDesc` blocks that pointed at them were
/// removed rather than allow-listed. That is the shape a resolved entry takes.
const Set<String> _knownMissing = <String>{
  'assets/documents/books/',
  'assets/documents/games/',
};

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

/// Every `filePath`, `fileBaseDir` and `docsDesc[].baseDir`+`title` in a
/// settings file, as repo-relative paths.
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

        final List<String> declared = _assetPathsIn(
          json.decode(file.readAsStringSync()),
        );
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
      // If a tree comes back, the allowance must go — otherwise the set stops
      // describing reality and the next reader trusts it.
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
      // The non-recursive trap. A directory that exists but is not listed ships
      // nothing, and rootBundle then fails at runtime exactly as if the file
      // were missing.
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
