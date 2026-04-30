import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:kataglyphis_inference_engine/settings/webrtc_settings.dart';
import 'package:permission_handler/permission_handler.dart';

// Web imports (only loaded on web)
// conditional import: stub for non-web, web impl for web
import 'package:kataglyphis_inference_engine/Pages/StreamPage/webrtc_view_stub.dart'
    if (dart.library.js_interop) 'package:kataglyphis_inference_engine/Pages/StreamPage/webrtc_view.dart'
    as webrtc_import;

// ============================================================================
// Constants
// ============================================================================

/// Default framerate for non-Android platforms (frames per second).
const int kDefaultFramerate = 30;

/// Maximum width constraint for WebRTC view container.
const double kWebRTCMaxWidth = 800.0;

/// Maximum height constraint for WebRTC view container.
const double kWebRTCMaxHeight = 600.0;

/// Border width for video containers.
const double kVideoBorderWidth = 2.0;

/// Border radius for WebRTC view container.
const double kWebRTCBorderRadius = 8.0;

/// Padding for error message containers.
const double kErrorPadding = 8.0;

/// Alpha value for error/warning background overlays.
const double kOverlayAlpha = 0.1;

/// Pixel format used for video conversion (RGBA for cross-platform compatibility).
const String kPixelFormat = 'RGBA';

// ============================================================================
// Pipeline Builder
// ============================================================================

/// Builds GStreamer pipeline strings for different video sources and platforms.
///
/// This class encapsulates all pipeline construction logic, making it easier
/// to test and maintain. Each method corresponds to a specific video source
/// or platform combination.
class GStreamerPipelineBuilder {
  /// Creates a pipeline builder with the specified dimensions and framerate.
  const GStreamerPipelineBuilder({
    required this.width,
    required this.height,
    required this.fps,
    required this.isAndroid,
  });

  /// Video width in pixels.
  final int width;

  /// Video height in pixels.
  final int height;

  /// Target framerate.
  final int fps;

  /// Whether building for Android platform.
  final bool isAndroid;

  /// Returns the appropriate sink element for the current platform.
  String get _sink => isAndroid
      ? 'glimagesink name=overlay qos=true sync=false max-lateness=20000000'
      : 'appsink name=sink emit-signals=true sync=false';

  /// Android conversion chain for camera-like sources.
  ///
  /// Does NOT force AHardwareBuffer/NV12 - different sources/devices negotiate
  /// different memory types and formats. Converts to RGBA for the sink.
  String get _androidGlConvertCamera =>
      'video/x-raw,width=$width,height=$height,framerate=$fps/1 '
      '! videoconvert ! video/x-raw,format=RGBA,width=$width,height=$height '
      '! glupload ! glcolorconvert';

  /// Android conversion chain for videotestsrc.
  ///
  /// videotestsrc produces system-memory frames; forcing AHardwareBuffer caps
  /// breaks preroll.
  String get _androidGlConvertTest =>
      'video/x-raw,width=$width,height=$height,framerate=$fps/1 '
      '! glupload ! glcolorconvert';

  /// Builds a pipeline string for the given video source.
  ///
  /// Supported sources:
  /// - 'videotestsrc': Test pattern (ball)
  /// - 'ahcsrc': Android Camera2 NDK
  /// - 'autovideosrc': Generic autodetect
  /// - 'v4l2src': Linux V4L2 camera
  /// - 'ksvideosrc': Windows camera
  /// - 'avfvideosrc': macOS camera
  /// - 'pattern-smpte': SMPTE test pattern
  /// - 'pattern-snow': Snow/noise test pattern
  String build(String source) {
    return switch (source) {
      'videotestsrc' => _buildTestPattern('ball'),
      'ahcsrc' => _buildAndroidCamera('ahcsrc'),
      'autovideosrc' => _buildAutoVideoSrc(),
      'v4l2src' => _buildV4L2Src(),
      'ksvideosrc' => _buildKsVideoSrc(),
      'avfvideosrc' => _buildAvfVideoSrc(),
      'pattern-smpte' => _buildTestPattern('smpte'),
      'pattern-snow' => _buildTestPattern('snow'),
      _ => _buildTestPattern('ball'),
    };
  }

  String _buildTestPattern(String pattern) {
    if (isAndroid) {
      return 'videotestsrc pattern=$pattern ! $_androidGlConvertTest ! $_sink';
    }
    return 'videotestsrc pattern=$pattern ! '
        'video/x-raw,width=$width,height=$height,framerate=$fps/1 ! $_sink';
  }

  String _buildAndroidCamera(String source) {
    if (isAndroid) {
      return '$source ! $_androidGlConvertCamera ! $_sink';
    }
    return '$source ! $_sink';
  }

  String _buildAutoVideoSrc() {
    if (isAndroid) {
      return 'autovideosrc ! $_androidGlConvertCamera ! $_sink';
    }
    return 'autovideosrc ! $_sink';
  }

  String _buildV4L2Src() {
    return 'v4l2src device=/dev/video0 ! '
        'image/jpeg,width=$width,height=$height,framerate=$fps/1 ! '
        'jpegdec ! videoconvert ! '
        'video/x-raw,format=$kPixelFormat,width=$width,height=$height ! $_sink';
  }

  String _buildKsVideoSrc() {
    return 'ksvideosrc device-index=0 ! videoconvert ! '
        'video/x-raw,format=$kPixelFormat,width=$width,height=$height,'
        'framerate=$fps/1 ! $_sink';
  }

  String _buildAvfVideoSrc() {
    return 'avfvideosrc capture-raw-data=true ! videoconvert ! '
        'video/x-raw,format=$kPixelFormat,width=$width,height=$height,'
        'framerate=$fps/1 ! $_sink';
  }
}

// ============================================================================
// StreamPage Widget
// ============================================================================

/// A page that displays video streams from various sources.
///
/// Supports multiple platforms:
/// - **Web**: Uses WebRTC for streaming
/// - **Desktop** (Windows, Linux, macOS): Uses native GStreamer textures
/// - **Android**: Uses GStreamer with camera fallback to WebRTC
///
/// Video sources are configurable and include camera inputs and test patterns.
class StreamPage extends StatefulWidget {
  /// The application-wide attributes for theming and layout.
  final AppAttributes appAttributes;

  /// The footer widget to display at the bottom of the page.
  final Footer footer;

  /// WebRTC and video configuration settings.
  final WebRTCSettings webrtcSettings;

  const StreamPage({
    super.key,
    required this.appAttributes,
    required this.footer,
    required this.webrtcSettings,
  });

  @override
  State<StatefulWidget> createState() => StreamPageState();
}

/// State for [StreamPage] managing native texture and playback.
class StreamPageState extends State<StreamPage> {
  // Native GStreamer setup
  static const MethodChannel channel = MethodChannel(
    'kataglyphis_native_inference',
  );

  late final Future<int?> textureId;

  // Texture dimensions from settings
  int get textureWidth => widget.webrtcSettings.texture.width;
  int get textureHeight => widget.webrtcSettings.texture.height;

  bool _isPlaying = false;
  String? _errorMessage;
  bool _nativeInitFailed = false;
  late final String _defaultNativeSource;

  // Android settings from webrtcSettings
  int get _androidWidth => widget.webrtcSettings.android.width;
  int get _androidHeight => widget.webrtcSettings.android.height;
  int get _androidFps => widget.webrtcSettings.android.fps;

  // Order: try modern Camera2 NDK (ahcsrc), then generic autodetect, then test pattern
  final List<String> _androidSourceCandidates = const <String>[
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

  /// Creates a pipeline builder configured for the current platform.
  GStreamerPipelineBuilder get _pipelineBuilder => GStreamerPipelineBuilder(
    width: _isAndroid ? _androidWidth : textureWidth,
    height: _isAndroid ? _androidHeight : textureHeight,
    fps: _isAndroid ? _androidFps : kDefaultFramerate,
    isAndroid: _isAndroid,
  );

  @override
  void initState() {
    super.initState();
    _defaultNativeSource = _pickDefaultSource();
    textureId = _initNativeIfNeeded();
  }

  String _pickDefaultSource() {
    if (_isWindows) return 'ksvideosrc';
    if (_isLinux) return 'v4l2src';
    if (_isMacOS) return 'avfvideosrc';
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
            _pipelineBuilder.build(_defaultNativeSource),
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

  Future<void> _setPipeline(String pipelineString, {String? source}) async {
    try {
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
      });

      if (_isPlaying) {
        await channel.invokeMethod('stop');
      }

      if (_isWindows) {
        await channel.invokeMethod('setPipeline', <String, String>{
          'pipeline': pipelineString,
        });
      } else {
        await channel.invokeMethod('setPipeline', pipelineString);
      }
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
            _pipelineBuilder.build(nextSource),
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
    if (idx == -1 || idx + 1 >= _androidSourceCandidates.length) return null;
    return _androidSourceCandidates[idx + 1];
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
    // Web: full WebRTC view
    if (kIsWeb) {
      return _buildWebView();
    }

    // Desktop + Android: Native GStreamer/Texture view
    if (_isWindows || _isLinux || _isMacOS || _isAndroid) {
      return _buildNativeView();
    }

    // Fallback for other platforms: WebRTC stub view
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
              _buildWebRTCContainer(
                child: webrtc_import.WebRTCView(
                  signalingUrl: widget.webrtcSettings.signalingServerUrl,
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

  Widget _buildWebRTCContainer({required Widget child}) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: kWebRTCMaxWidth,
        maxHeight: kWebRTCMaxHeight,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: kVideoBorderWidth),
        borderRadius: BorderRadius.circular(kWebRTCBorderRadius),
      ),
      child: child,
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
              if (_errorMessage != null) _buildErrorMessage(_errorMessage!),
              _buildTextureWidget(),
              _buildPlaybackStatus(),
              const Divider(),
              _buildSectionTitle('GStreamer Controls'),
              _buildPlaybackControls(),
              const Divider(),
              _buildSectionTitle('Video Sources'),
              _buildVideoSourceButtons(),
              if (!_isAndroid) ...[
                const Divider(),
                _buildSectionTitle('Static Colors (Legacy)'),
                _buildColorButtons(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(kErrorPadding),
      color: Colors.red.withValues(alpha: kOverlayAlpha),
      child: Text(message, style: const TextStyle(color: Colors.red)),
    );
  }

  Widget _buildTextureWidget() {
    return FutureBuilder<int?>(
      future: textureId,
      builder: (BuildContext context, AsyncSnapshot<int?> snapshot) {
        final bool rotateAndroidRight = _isAndroid;
        final double displayWidth =
            (rotateAndroidRight ? _targetTextureHeight : _targetTextureWidth)
                .toDouble();
        final double displayHeight =
            (rotateAndroidRight ? _targetTextureWidth : _targetTextureHeight)
                .toDouble();

        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: displayWidth,
            height: displayHeight,
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
            return _buildAndroidFallback('Error creating texture (null id)');
          }
          return const Text('Error creating texture (null id)');
        }

        if (_isAndroid && _nativeInitFailed) {
          return _buildAndroidFallback('Native init failed');
        }

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey, width: kVideoBorderWidth),
          ),
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: rotateAndroidRight
                ? RotatedBox(
                    quarterTurns: 1,
                    child: Texture(textureId: snapshot.data!),
                  )
                : Texture(textureId: snapshot.data!),
          ),
        );
      },
    );
  }

  Widget _buildPlaybackStatus() {
    return Text(
      _isPlaying ? 'Playing' : 'Paused',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: _isPlaying ? Colors.green : Colors.orange,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildPlaybackControls() {
    return Row(
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
    );
  }

  Widget _buildVideoSourceButtons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        if (_isAndroid) ..._buildAndroidSourceButtons(),
        if (!_isAndroid) ..._buildDesktopSourceButtons(),
      ],
    );
  }

  List<Widget> _buildAndroidSourceButtons() {
    return [
      _buildSourceButton(
        icon: Icons.sports_soccer,
        label: 'Test Pattern',
        source: 'videotestsrc',
      ),
      _buildSourceButton(
        icon: Icons.videocam,
        label: 'Camera (ahc2src)',
        source: 'ahc2src',
      ),
      _buildSourceButton(
        icon: Icons.auto_awesome,
        label: 'Auto Camera',
        source: 'autovideosrc',
      ),
    ];
  }

  List<Widget> _buildDesktopSourceButtons() {
    return [
      _buildSourceButton(
        icon: Icons.sports_soccer,
        label: 'Test Pattern (Ball)',
        source: 'videotestsrc',
      ),
      _buildSourceButton(
        icon: Icons.grid_on,
        label: 'SMPTE Pattern',
        source: 'pattern-smpte',
      ),
      _buildSourceButton(
        icon: Icons.grain,
        label: 'Snow Pattern',
        source: 'pattern-snow',
      ),
      if (_isWindows)
        _buildSourceButton(
          icon: Icons.videocam,
          label: 'Windows Camera (ksvideosrc)',
          source: 'ksvideosrc',
        ),
      if (_isLinux)
        _buildSourceButton(
          icon: Icons.videocam,
          label: 'Webcam (/dev/video0)',
          source: 'v4l2src',
        ),
      if (_isMacOS)
        _buildSourceButton(
          icon: Icons.videocam,
          label: 'Mac Camera (avfvideosrc)',
          source: 'avfvideosrc',
        ),
    ];
  }

  Widget _buildSourceButton({
    required IconData icon,
    required String label,
    required String source,
  }) {
    return OutlinedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: () =>
          _setPipeline(_pipelineBuilder.build(source), source: source),
    );
  }

  Widget _buildColorButtons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        _buildColorButton('Flutter Navy', 0x04, 0x2b, 0x59),
        _buildColorButton('Flutter Blue', 0x05, 0x53, 0xb1),
        _buildColorButton('Flutter Sky', 0x02, 0x7d, 0xfd),
        _buildColorButton('Red', 0xf2, 0x5d, 0x50),
        _buildColorButton('Yellow', 0xff, 0xf2, 0x75),
        _buildColorButton('Purple', 0x62, 0x00, 0xee),
        _buildColorButton('Green', 0x1c, 0xda, 0xc5),
      ],
    );
  }

  Widget _buildColorButton(String label, int r, int g, int b) {
    return OutlinedButton(
      onPressed: () => setColor(r, g, b),
      child: Text(label),
    );
  }

  Widget _buildAndroidFallback(String? reason) {
    final String message =
        reason ?? _errorMessage ?? 'Native texture unavailable';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(kErrorPadding),
          color: Colors.orange.withValues(alpha: kOverlayAlpha),
          child: Text(
            'Falling back to WebRTC preview on Android. Reason: $message',
            style: const TextStyle(color: Colors.orange),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        _buildWebRTCContainer(
          child: webrtc_import.WebRTCView(
            signalingUrl: widget.webrtcSettings.signalingServerUrl,
            producerIdToConsume: null,
          ),
        ),
      ],
    );
  }
}
