import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:permission_handler/permission_handler.dart';

// Web imports (only loaded on web)
// conditional import: stub for non-web, web impl for web
import 'package:kataglyphis_inference_engine/Pages/StreamPage/webrtc_view_stub.dart'
    if (dart.library.html) 'package:kataglyphis_inference_engine/Pages/StreamPage/webrtc_view.dart'
    as webrtc_import;

class StreamPage extends StatefulWidget {
  final AppAttributes appAttributes;
  final Footer footer;

  const StreamPage({
    super.key,
    required this.appAttributes,
    required this.footer,
  });

  @override
  State<StatefulWidget> createState() => StreamPageState();
}

class StreamPageState extends State<StreamPage> {
  // Native GStreamer setup
  static const MethodChannel channel = MethodChannel(
    'kataglyphis_native_inference',
  );
  late final Future<int?> textureId;
  static const int textureWidth = 640;
  static const int textureHeight = 480;

  bool _isPlaying = false;
  String? _errorMessage;
  bool _nativeInitFailed = false;
  late final String _defaultNativeSource;
  static const int _androidWidth = 320;
  static const int _androidHeight = 240;
  static const int _androidFps = 15;
  // Order: try modern Camera2 NDK (ahcsrc), then generic autodetect, then test pattern
  // ahc2src and androidvideosource are not available in current GStreamer builds
  final List<String> _androidSourceCandidates = <String>[
    'ahcsrc',
    'autovideosrc',
    'videotestsrc',
  ];

  int get _targetTextureWidth => _isAndroid ? _androidWidth : textureWidth;
  int get _targetTextureHeight => _isAndroid ? _androidHeight : textureHeight;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _isLinux => defaultTargetPlatform == TargetPlatform.linux;
  bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();

    _defaultNativeSource = _pickDefaultSource();

    // Native Integration für Desktop + Android initialisieren (nach Android-Permission)
    textureId = _initNativeIfNeeded();
  }

  String _pickDefaultSource() {
    if (_isWindows) return 'ksvideosrc';
    if (_isLinux) return 'v4l2src';
    if (_isMacOS) return 'avfvideosrc';
    // On Android, prefer ahcsrc (Camera2 NDK) which is more stable than older Camera1 API
    if (_isAndroid) return 'ahcsrc';
    return 'videotestsrc';
  }

  Future<int?> _initNativeIfNeeded() async {
    if (kIsWeb || !(_isWindows || _isLinux || _isMacOS || _isAndroid)) {
      return null;
    }

    if (_isAndroid) {
      final bool granted = await _ensureCameraPermission();
      if (!granted) return null;
    }

    return _initializeNative();
  }

  Future<bool> _ensureCameraPermission() async {
    final PermissionStatus status = await Permission.camera.request();

    if (status.isGranted) return true;

    if (mounted) {
      setState(() {
        _errorMessage = 'Camera permission is required to start the stream.';
      });
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  Future<int?> _initializeNative() {
    return channel
        .invokeMethod<int>('create', <int>[
          _targetTextureWidth,
          _targetTextureHeight,
        ])
        .then((id) async {
          await _setPipeline(
            _buildPipelineString(_defaultNativeSource),
            source: _defaultNativeSource,
          );
          return id;
        })
        .catchError((e) {
          debugPrint('create texture error: $e');
          if (mounted) {
            setState(() {
              _errorMessage = 'Texture creation failed: $e';
              _nativeInitFailed = true;
            });
          }
          throw e;
        });
  }

  String _buildPipelineString(String source) {
    final bool useOverlaySink = _isAndroid;
    // Force RGBA on Android to avoid NV12/AHardwareBuffer format negotiation errors on Adreno.
    const String pixelFormat = 'RGBA';
    final int w = _isAndroid ? _androidWidth : textureWidth;
    final int h = _isAndroid ? _androidHeight : textureHeight;
    final int fps = _isAndroid ? _androidFps : 30;

    // Use glimagesink on Android for hardware rendering, appsink for other platforms
    final String sink = useOverlaySink
        ? 'glimagesink name=overlay qos=true sync=false max-lateness=20000000'
        : 'appsink name=sink emit-signals=true sync=false';

    // Android conversion chain for camera-like sources.
    // Do NOT force AHardwareBuffer/NV12 here: different sources/devices negotiate different
    // memory types and formats. We keep caps to size/fps and convert to RGBA for the sink.
    // NOTE: DO NOT add caps constraints after glcolorconvert - let it auto-negotiate
    final String androidGlConvertCamera =
        'video/x-raw,width=$w,height=$h,framerate=$fps/1 '
        // Some Android camera sources output formats (e.g. NV21) that glupload can't always
        // negotiate directly; videoconvert makes the pipeline far more robust.
        '! videoconvert ! video/x-raw,format=RGBA,width=$w,height=$h '
        '! glupload ! glcolorconvert';

    // Android conversion chain for videotestsrc.
    // videotestsrc produces system-memory frames; forcing AHardwareBuffer caps breaks preroll.
    final String androidGlConvertTest =
        'video/x-raw,width=$w,height=$h,framerate=$fps/1 '
        '! glupload ! glcolorconvert';

    switch (source) {
      case 'videotestsrc':
        // Test pattern: safe baseline to verify GStreamer/glimagesink works
        if (_isAndroid) {
          return 'videotestsrc pattern=ball ! $androidGlConvertTest ! $sink';
        }
        return 'videotestsrc pattern=ball ! video/x-raw,width=$w,height=$h,framerate=$fps/1 ! $sink';
      case 'ahcsrc':
        // Android Camera2 NDK-based source - most stable camera source
        if (_isAndroid) {
          return 'ahcsrc ! $androidGlConvertCamera ! $sink';
        }
        return 'ahcsrc ! $sink';
      case 'autovideosrc':
        // Generic autodetect: lets GStreamer pick the best available platform source
        if (_isAndroid) {
          return 'autovideosrc ! $androidGlConvertCamera ! $sink';
        }
        return 'autovideosrc ! $sink';
      case 'v4l2src':
        return 'v4l2src device=/dev/video0 ! image/jpeg,width=$w,height=$h,framerate=$fps/1 ! jpegdec ! videoconvert ! video/x-raw,format=$pixelFormat,width=$w,height=$h ! $sink';
      case 'ksvideosrc':
        return 'ksvideosrc device-index=0 ! videoconvert ! video/x-raw,format=$pixelFormat,width=$w,height=$h,framerate=$fps/1 ! $sink';
      case 'avfvideosrc':
        return 'avfvideosrc capture-raw-data=true ! videoconvert ! video/x-raw,format=$pixelFormat,width=$w,height=$h,framerate=$fps/1 ! $sink';
      case 'pattern-smpte':
        if (_isAndroid) {
          return 'videotestsrc pattern=smpte ! $androidGlConvertTest ! $sink';
        }
        return 'videotestsrc pattern=smpte ! video/x-raw,width=$w,height=$h,framerate=$fps/1 ! $sink';
      case 'pattern-snow':
        if (_isAndroid) {
          return 'videotestsrc pattern=snow ! $androidGlConvertTest ! $sink';
        }
        return 'videotestsrc pattern=snow ! video/x-raw,width=$w,height=$h,framerate=$fps/1 ! $sink';
      default:
        if (_isAndroid) {
          return 'videotestsrc pattern=ball ! $androidGlConvertTest ! $sink';
        }
        return 'videotestsrc pattern=ball ! video/x-raw,width=$w,height=$h,framerate=$fps/1 ! $sink';
    }
  }

  Future<void> _setPipeline(String pipelineString, {String? source}) async {
    try {
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
      });

      if (_isPlaying) {
        await channel.invokeMethod('stop');
      }

      await channel.invokeMethod('setPipeline', pipelineString);
      await channel.invokeMethod('play');

      if (!mounted) return;
      setState(() {
        _isPlaying = true;
      });

      debugPrint('Pipeline set and playing: $pipelineString');
    } on PlatformException catch (e) {
      debugPrint('setPipeline failed: $e');
      final message = e.message ?? '';
      final bool missingElement =
          message.contains('no element') || message.contains('not found');
      final bool shouldRetryAndroid =
          _isAndroid &&
          source != null &&
          (missingElement || e.code == 'command_failed');

      if (shouldRetryAndroid) {
        // Print native-side diagnostics once per failure to avoid guesswork.
        // This does not change UX, it only improves logs.
        final String? diag = await channel
            .invokeMethod<String>('diagnose')
            .catchError((_) => null);
        if (diag != null && diag.isNotEmpty) {
          debugPrint('GStreamer diagnose:\n$diag');
        }

        final String? nextSource = _nextAndroidSource(source);
        if (nextSource != null) {
          debugPrint(
            missingElement
                ? 'Android pipeline "$source" missing; trying "$nextSource"'
                : 'Android pipeline "$source" failed; trying "$nextSource"',
          );
          await _setPipeline(
            _buildPipelineString(nextSource),
            source: nextSource,
          );
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _errorMessage = _isAndroid && shouldRetryAndroid
            ? 'GStreamer pipeline failed on Android (tried: ${_androidSourceCandidates.join(', ')}). See logs for diagnose output.'
            : 'Pipeline error: ${e.message}';
        _isPlaying = false;
      });
    }
  }

  String? _nextAndroidSource(String failedSource) {
    final int idx = _androidSourceCandidates.indexOf(failedSource);
    if (idx == -1) return null;
    if (idx + 1 < _androidSourceCandidates.length) {
      return _androidSourceCandidates[idx + 1];
    }
    return null;
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await channel.invokeMethod('pause');
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
        });
      } else {
        await channel.invokeMethod('play');
        if (!mounted) return;
        setState(() {
          _isPlaying = true;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('togglePlayPause failed: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Play/Pause error: ${e.message}';
      });
    }
  }

  Future<void> _stopPipeline() async {
    try {
      await channel.invokeMethod('stop');
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
      });
    } on PlatformException catch (e) {
      debugPrint('stop failed: $e');
    }
  }

  @override
  void dispose() {
    channel
        .invokeMethod('stop')
        .catchError((e) => debugPrint('stop on dispose failed: $e'));
    _isPlaying = false;
    super.dispose();
  }

  Future<void> setColor(int r, int g, int b) async {
    try {
      await channel.invokeMethod('setColor', <int>[r, g, b]);
    } on PlatformException catch (e) {
      debugPrint('setColor failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Web: vollwertige WebRTC-Ansicht
    if (kIsWeb) {
      return _buildWebView();
    }

    // Desktop + Android: Native GStreamer-/Texture-Ansicht
    if (_isWindows || _isLinux || _isMacOS || _isAndroid) {
      return _buildNativeView();
    }

    // Fallback für andere Plattformen:
    // Zeige die WebRTC-Stub-Ansicht (reine Flutter-UI, kein Native-Code).
    return _buildWebView();
  }

  Widget _buildWebView() {
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              Container(
                constraints: const BoxConstraints(
                  maxWidth: 800,
                  maxHeight: 600,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: webrtc_import.WebRTCView(
                  signalingUrl: 'ws://127.0.0.1:8443',
                  producerIdToConsume: null,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'WebRTC Stream',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNativeView() {
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: <Widget>[
              // Error message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.withValues(alpha: 0.1),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              // Texture widget
              FutureBuilder<int?>(
                future: textureId,
                builder: (BuildContext context, AsyncSnapshot<int?> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                      width: _targetTextureWidth.toDouble(),
                      height: _targetTextureHeight.toDouble(),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    if (_isAndroid) {
                      return _buildAndroidFallback(snapshot.error?.toString());
                    }
                    return SizedBox(
                      width: textureWidth.toDouble(),
                      height: textureHeight.toDouble(),
                      child: Center(child: Text('Error: ${snapshot.error}')),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data == null) {
                    if (_isAndroid) {
                      return _buildAndroidFallback(
                        'Error creating texture (null id)',
                      );
                    }
                    return const Text('Error creating texture (null id)');
                  }

                  if (_isAndroid && _nativeInitFailed) {
                    return _buildAndroidFallback('Native init failed');
                  }

                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey, width: 2),
                    ),
                    child: SizedBox(
                      width: _targetTextureWidth.toDouble(),
                      height: _targetTextureHeight.toDouble(),
                      child: Texture(textureId: snapshot.data!),
                    ),
                  );
                },
              ),

              // Status display
              Text(
                _isPlaying ? 'Playing' : 'Paused',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isPlaying ? Colors.green : Colors.orange,
                ),
              ),

              const Divider(),
              const Text(
                'GStreamer Controls',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              // Play/Pause buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 10,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(_isPlaying ? 'Pause' : 'Play'),
                    onPressed: _togglePlayPause,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    onPressed: _stopPipeline,
                  ),
                ],
              ),

              const Divider(),
              const Text(
                'Video Sources',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              // Pipeline buttons
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (_isAndroid) ...[
                    // Test pattern - safe baseline
                    OutlinedButton.icon(
                      icon: const Icon(Icons.sports_soccer),
                      label: const Text('Test Pattern'),
                      onPressed: () {
                        _setPipeline(
                          _buildPipelineString('videotestsrc'),
                          source: 'videotestsrc',
                        );
                      },
                    ),
                    // Camera2 (Modern Pixel 4)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Camera (ahc2src)'),
                      onPressed: () {
                        _setPipeline(
                          _buildPipelineString('ahc2src'),
                          source: 'ahc2src',
                        );
                      },
                    ),
                    // Autodetect - best available
                    OutlinedButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Auto Camera'),
                      onPressed: () {
                        _setPipeline(
                          _buildPipelineString('autovideosrc'),
                          source: 'autovideosrc',
                        );
                      },
                    ),
                  ],
                  if (!_isAndroid)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.sports_soccer),
                      label: const Text('Test Pattern (Ball)'),
                      onPressed: () {
                        _setPipeline(_buildPipelineString('videotestsrc'));
                      },
                    ),
                  if (!_isAndroid)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.grid_on),
                      label: const Text('SMPTE Pattern'),
                      onPressed: () {
                        _setPipeline(_buildPipelineString('pattern-smpte'));
                      },
                    ),
                  if (!_isAndroid)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.grain),
                      label: const Text('Snow Pattern'),
                      onPressed: () {
                        _setPipeline(_buildPipelineString('pattern-snow'));
                      },
                    ),
                  if (_isWindows)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Windows Camera (ksvideosrc)'),
                      onPressed: () {
                        _setPipeline(_buildPipelineString('ksvideosrc'));
                      },
                    ),
                  if (_isLinux)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Webcam (/dev/video0)'),
                      onPressed: () {
                        _setPipeline(_buildPipelineString('v4l2src'));
                      },
                    ),
                  if (_isMacOS)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Mac Camera (avfvideosrc)'),
                      onPressed: () {
                        _setPipeline(_buildPipelineString('avfvideosrc'));
                      },
                    ),
                ],
              ),

              if (!_isAndroid) ...[
                const Divider(),
                const Text(
                  'Static Colors (Legacy)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                // Color buttons (only relevant for videotestsrc)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      child: const Text('Flutter Navy'),
                      onPressed: () => setColor(0x04, 0x2b, 0x59),
                    ),
                    OutlinedButton(
                      child: const Text('Flutter Blue'),
                      onPressed: () => setColor(0x05, 0x53, 0xb1),
                    ),
                    OutlinedButton(
                      child: const Text('Flutter Sky'),
                      onPressed: () => setColor(0x02, 0x7d, 0xfd),
                    ),
                    OutlinedButton(
                      child: const Text('Red'),
                      onPressed: () => setColor(0xf2, 0x5d, 0x50),
                    ),
                    OutlinedButton(
                      child: const Text('Yellow'),
                      onPressed: () => setColor(0xff, 0xf2, 0x75),
                    ),
                    OutlinedButton(
                      child: const Text('Purple'),
                      onPressed: () => setColor(0x62, 0x00, 0xee),
                    ),
                    OutlinedButton(
                      child: const Text('Green'),
                      onPressed: () => setColor(0x1c, 0xda, 0xc5),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAndroidFallback(String? reason) {
    final String message =
        reason ?? _errorMessage ?? 'Native texture unavailable';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.orange.withValues(alpha: 0.1),
          child: Text(
            'Falling back to WebRTC preview on Android. Reason: $message',
            style: const TextStyle(color: Colors.orange),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: webrtc_import.WebRTCView(
            signalingUrl: 'ws://127.0.0.1:8443',
            producerIdToConsume: null,
          ),
        ),
      ],
    );
  }
}
