// Pins the pipeline strings: a typo there only fails on a machine with a camera, which CI lacks.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_accelerant/Pages/StreamPage/gstreamer_pipeline.dart';

void main() {
  _fallbackPolicyTests();
  const GStreamerPipelineBuilder desktop = GStreamerPipelineBuilder(
    width: 640,
    height: 480,
    fps: 30,
    isAndroid: false,
  );

  const GStreamerPipelineBuilder android = GStreamerPipelineBuilder(
    width: 320,
    height: 240,
    fps: 15,
    isAndroid: true,
  );

  group('sink selection', () {
    test('desktop terminates in the appsink the plugin looks up by name', () {
      // A desktop plugin finds its appsink by the name "sink" and fails setPipeline without it.
      for (final String source in <String>[
        'videotestsrc',
        'avfvideosrc',
        'pattern-smpte',
        'pattern-snow',
      ]) {
        expect(
          desktop.build(source),
          contains('appsink name=sink'),
          reason: '$source must end in the appsink the plugin resolves',
        );
      }
    });

    test('android renders through glimagesink instead of an appsink', () {
      expect(android.build('ahcsrc'), contains('glimagesink name=overlay'));
      expect(android.build('ahcsrc'), isNot(contains('appsink')));
    });

    test('both android camera sources build a camera, not the ball', () {
      // The page's camera button sends ahc2src; unknown, it fell through to the test pattern.
      for (final String source in <String>['ahcsrc', 'ahc2src']) {
        expect(android.build(source), startsWith('$source ! '));
        expect(android.build(source), isNot(contains('videotestsrc')));
      }
    });
  });

  group('avfvideosrc — the macOS default', () {
    // The exact string macOS negotiates on page open.
    final String pipeline = desktop.build('avfvideosrc');

    test('asks the camera for raw frames', () {
      expect(pipeline, startsWith('avfvideosrc capture-raw-data=true ! '));
    });

    test('converts to RGBA, which is the only format the appsink accepts', () {
      // Any other format prerolls against the RGBA-pinned appsink and never delivers a sample.
      expect(pipeline, contains('format=RGBA'));
    });

    test('carries the configured geometry and framerate', () {
      expect(pipeline, contains('width=640'));
      expect(pipeline, contains('height=480'));
      expect(pipeline, contains('framerate=30/1'));
    });
  });

  group('test patterns', () {
    test('named patterns reach videotestsrc', () {
      expect(desktop.build('pattern-smpte'), contains('pattern=smpte'));
      expect(desktop.build('pattern-snow'), contains('pattern=snow'));
      expect(desktop.build('videotestsrc'), contains('pattern=ball'));
    });

    test('an unknown source falls back to the ball pattern', () {
      // The result goes straight to gst_parse_launch, so it must stay playable.
      expect(
        desktop.build('no-such-source'),
        equals(desktop.build('videotestsrc')),
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
            in <GStreamerPipelineBuilder>[desktop, android]) {
          for (final String source in <String>[
            'videotestsrc',
            'ahcsrc',
            'autovideosrc',
            'avfvideosrc',
            'pattern-smpte',
            'pattern-snow',
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

    test('macOS tries its camera first, then degrades', () {
      expect(sourceCandidatesFor(TargetPlatform.macOS), <String>[
        'avfvideosrc',
        'videotestsrc',
      ]);
    });

    test(
      'Windows and Linux have no plugin chain: the Rust core owns their camera',
      () {
        expect(kSourceCandidates.keys, <TargetPlatform>[
          TargetPlatform.android,
          TargetPlatform.macOS,
        ]);
      },
    );

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
      expect(nextSourceAfter('pattern-snow', chain), isNull);
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
