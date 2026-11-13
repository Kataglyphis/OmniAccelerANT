// Pins the pipeline strings: a typo there only fails on a machine with a camera, which CI lacks.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_accelerant/Pages/StreamPage/gstreamer_pipeline.dart';

void main() {
  _fallbackPolicyTests();
  const GStreamerPipelineBuilder android = GStreamerPipelineBuilder(
    width: 320,
    height: 240,
    fps: 15,
  );

  group('sink selection', () {
    test(
      'every source renders through the GL sink the plugin names overlay',
      () {
        for (final String source in <String>[
          'videotestsrc',
          'ahcsrc',
          'ahc2src',
          'autovideosrc',
        ]) {
          expect(android.build(source), contains('glimagesink name=overlay'));
          expect(android.build(source), isNot(contains('appsink')));
        }
      },
    );

    test('both android camera sources build a camera, not the ball', () {
      // The page's camera button sends ahc2src; unknown, it fell through to the test pattern.
      for (final String source in <String>['ahcsrc', 'ahc2src']) {
        expect(android.build(source), startsWith('$source ! '));
        expect(android.build(source), isNot(contains('videotestsrc')));
      }
    });
  });

  group('test patterns', () {
    test('the test pattern is the ball, and an unknown source falls back to it', () {
      // The result goes straight to gst_parse_launch, so it must stay playable.
      expect(android.build('videotestsrc'), contains('pattern=ball'));
      expect(
        android.build('no-such-source'),
        equals(android.build('videotestsrc')),
      );
    });

    test('android test patterns skip the camera conversion chain', () {
      // System-memory frames break preroll under the camera chain's caps.
      final String pattern = android.build('videotestsrc');
      expect(pattern, contains('glupload'));
      expect(pattern, isNot(contains('videoconvert')));
    });

    test('android camera sources keep the videoconvert step', () {
      expect(android.build('ahcsrc'), contains('videoconvert'));
      expect(android.build('autovideosrc'), contains('videoconvert'));
    });
  });

  group('geometry propagation', () {
    test('android uses its own smaller geometry', () {
      final String pipeline = android.build('ahcsrc');
      expect(pipeline, contains('width=320'));
      expect(pipeline, contains('height=240'));
      expect(pipeline, contains('framerate=15/1'));
    });

    test(
      'every produced pipeline is non-empty and has no double separators',
      () {
        for (final GStreamerPipelineBuilder builder
            in <GStreamerPipelineBuilder>[android]) {
          for (final String source in <String>[
            'videotestsrc',
            'ahcsrc',
            'ahc2src',
            'autovideosrc',
            'garbage',
          ]) {
            final String pipeline = builder.build(source);
            expect(pipeline, isNotEmpty);
            expect(
              pipeline,
              isNot(contains('! !')),
              reason:
                  'an empty element between two links fails gst_parse_launch',
            );
            expect(
              pipeline.trim(),
              equals(pipeline.replaceAll('  ', ' ').trim()),
            );
          }
        }
      },
    );
  });
}

// Source fallback policy

void _fallbackPolicyTests() {
  group('source fallback chains', () {
    test('every platform ends in a source that needs no hardware', () {
      for (final TargetPlatform platform in kSourceCandidates.keys) {
        expect(
          sourceCandidatesFor(platform).last,
          'videotestsrc',
          reason:
              '$platform must degrade to a test pattern, so an absent camera '
              'still proves the app itself works',
        );
      }
    });

    test('android tries its camera, then any camera, then degrades', () {
      expect(sourceCandidatesFor(TargetPlatform.android), <String>[
        'ahcsrc',
        'autovideosrc',
        'videotestsrc',
      ]);
    });

    test('only Android has a plugin chain: the Rust core owns the desktop camera, and macOS is no target', () {
      expect(kSourceCandidates.keys, <TargetPlatform>[TargetPlatform.android]);
    });

    test('an unlisted platform still gets a usable chain', () {
      expect(sourceCandidatesFor(TargetPlatform.fuchsia), <String>[
        'videotestsrc',
      ]);
    });

    test('no chain is empty and none repeats a source', () {
      for (final TargetPlatform platform in kSourceCandidates.keys) {
        final List<String> chain = sourceCandidatesFor(platform);
        expect(chain, isNotEmpty);
        expect(chain.toSet().length, chain.length, reason: '$platform repeats');
      }
    });
  });

  group('nextSourceAfter', () {
    const List<String> chain = <String>['a', 'b', 'c'];

    test('walks the chain in order', () {
      expect(nextSourceAfter('a', chain), 'b');
      expect(nextSourceAfter('b', chain), 'c');
    });

    test('returns null at the end so the retry terminates', () {
      expect(nextSourceAfter('c', chain), isNull);
    });

    test('returns null for a source outside the chain', () {
      // A hand-picked source keeps its own error instead of restarting the chain.
      expect(nextSourceAfter('ahc2src', chain), isNull);
    });

    test('the real android chain terminates from any starting point', () {
      final List<String> chain = sourceCandidatesFor(TargetPlatform.android);
      String? current = chain.first;
      int steps = 0;
      while (current != null) {
        current = nextSourceAfter(current, chain);
        expect(++steps, lessThanOrEqualTo(chain.length));
      }
      expect(steps, chain.length);
    });
  });
}
