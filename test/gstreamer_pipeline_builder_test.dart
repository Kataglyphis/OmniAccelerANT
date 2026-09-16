// Unit tests for the GStreamer pipeline strings the Stream page hands to the
// native plugin.
//
// These are worth pinning because the strings are the API boundary between Dart
// and GStreamer: a typo in one of them is not a compile error, not an analyzer
// warning and not visible in a widget test — it surfaces as a live pipeline that
// fails to reach PLAYING on a machine with a camera attached, which is the one
// configuration CI does not have.
//
// GStreamerPipelineBuilder is pure and takes no BuildContext, so all of this
// runs in the VM with no binding, no platform channel and no device.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_accelerant/Pages/StreamPage/stream_page.dart';

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
      // my_texture.cc does gst_bin_get_by_name(pipeline, "sink") and fails the
      // whole setPipeline call when that returns nothing, so the name is a
      // contract and not a label.
      for (final String source in <String>[
        'videotestsrc',
        'v4l2src',
        'ksvideosrc',
        'avfvideosrc',
        'pattern-smpte',
        'pattern-snow',
      ]) {
        expect(
          desktop.build(source),
          contains('appsink name=sink'),
          reason: '$source must end in the appsink the Linux plugin resolves',
        );
      }
    });

    test('android renders through glimagesink instead of an appsink', () {
      expect(android.build('ahcsrc'), contains('glimagesink name=overlay'));
      expect(android.build('ahcsrc'), isNot(contains('appsink')));
    });
  });

  group('v4l2src — the Linux default', () {
    // _pickDefaultSource() returns 'v4l2src' on Linux and initState plays it
    // immediately, so this exact string is what a Linux desktop run negotiates
    // on page open.
    final String pipeline = desktop.build('v4l2src');

    test('opens /dev/video0', () {
      expect(pipeline, contains('v4l2src device=/dev/video0'));
    });

    test('decodes MJPEG rather than assuming raw frames', () {
      expect(pipeline, contains('image/jpeg'));
      expect(pipeline, contains('jpegdec'));
    });

    test('converts to RGBA, which is the only format the appsink accepts', () {
      // my_texture_set_pipeline pins the appsink caps to video/x-raw,
      // format=RGBA. A pipeline that negotiates anything else prerolls and then
      // never delivers a sample.
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
      // Documented behaviour of the `_ =>` arm: an unrecognised source must
      // still produce a playable pipeline rather than an empty string, because
      // the result goes straight to gst_parse_launch.
      expect(
        desktop.build('no-such-source'),
        equals(desktop.build('videotestsrc')),
      );
    });

    test('android test patterns skip the camera conversion chain', () {
      // videotestsrc produces system-memory frames; forcing the camera chain's
      // AHardwareBuffer caps on them breaks preroll.
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
            'v4l2src',
            'ksvideosrc',
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

// ---------------------------------------------------------------------------
// Source fallback policy
// ---------------------------------------------------------------------------
//
// These pin the chain itself rather than any one pipeline string. The Linux row
// is the reason the policy exists: before 2026-09-16 only Android retried, so a
// Linux machine with no /dev/video0 showed a dead texture and nothing else.

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

    test('linux tries the V4L2 camera first, then degrades', () {
      expect(sourceCandidatesFor(TargetPlatform.linux), <String>[
        'v4l2src',
        'autovideosrc',
        'videotestsrc',
      ]);
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
      // A hand-picked source must fail with its own error rather than silently
      // restarting the platform chain from the middle.
      expect(nextSourceAfter('pattern-snow', chain), isNull);
    });

    test('the real linux chain terminates from any starting point', () {
      final List<String> chain = sourceCandidatesFor(TargetPlatform.linux);
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
