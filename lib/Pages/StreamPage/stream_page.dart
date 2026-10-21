import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/Layout/ResponsiveDesign/single_page.dart';
import 'package:anthology/app_attributes.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';
import 'package:omni_accelerant/Pages/StreamPage/gstreamer_pipeline.dart';
import 'package:permission_handler/permission_handler.dart';

// Stub on native, the WebRTC view on web.
import 'package:omni_accelerant/Pages/StreamPage/webrtc_view_stub.dart'
    if (dart.library.js_interop) 'package:omni_accelerant/Pages/StreamPage/webrtc_view.dart'
    as webrtc_import;
import 'package:omni_accelerant/Pages/StreamPage/rust_webcam_view.dart';
import 'package:omni_accelerant/Pages/StreamPage/detection_status.dart';
import 'package:omni_accelerant/Pages/StreamPage/camera_peers.dart';
import 'package:omni_accelerant/Pages/StreamPage/dev_stats.dart';
import 'package:omni_accelerant/Pages/StreamPage/visit_stats.dart';
// Nothing on native; on web ObservANT that serves the page (its /healthz, here).
import 'package:omni_accelerant/Pages/StreamPage/observant_api_stub.dart'
    if (dart.library.js_interop) 'package:omni_accelerant/Pages/StreamPage/observant_api_web.dart';

// Constants

/// Maximum width constraint for WebRTC view container.
const double kWebRTCMaxWidth = 800.0;

/// Maximum height constraint for WebRTC view container.
const double kWebRTCMaxHeight = 600.0;

/// ObservANT's 640x480: a box of the stream's shape leaves no empty band above and below it on a phone.
const double kWebRTCAspectRatio = 4 / 3;

/// Border width for video containers.
const double kVideoBorderWidth = 2.0;

/// Border radius for WebRTC view container.
const double kWebRTCBorderRadius = 8.0;

/// Padding for error message containers.
const double kErrorPadding = 8.0;

/// Alpha value for error/warning background overlays.
const double kOverlayAlpha = 0.1;

// StreamPage Widget

/// Video stream page: WebRTC on web, the Rust webcam on Windows and Linux, the plugin's GStreamer texture on Android and macOS.
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

  /// This platform's fallback chain — see [kSourceCandidates].
  List<String> get _sourceCandidates =>
      sourceCandidatesFor(defaultTargetPlatform);

  int get _targetTextureWidth => _isAndroid ? _androidWidth : textureWidth;
  int get _targetTextureHeight => _isAndroid ? _androidHeight : textureHeight;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _isLinux => defaultTargetPlatform == TargetPlatform.linux;

  /// The target decides: the Rust core drives the webcam on Windows and Linux.
  bool get _useRustWebcam => _isWindows || _isLinux;

  /// Android and macOS, where the Rust webcam cannot run, play the plugin's own GStreamer pipeline.
  bool get _usePluginPipeline => !kIsWeb && (_isMacOS || _isAndroid);

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

  String _pickDefaultSource() => _sourceCandidates.first;

  Future<int?> _initNativeIfNeeded() async {
    // The Rust view creates the plugin's single texture itself; a second create would race it.
    if (!_usePluginPipeline) return null;

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
      // A missing element or failed state change falls back, from a source on the chain only: a button off it reports its own error.
      final bool shouldRetry =
          source != null &&
          _sourceCandidates.contains(source) &&
          (missingElement || e.code == 'command_failed');

      if (shouldRetry) {
        final String? diag = await channel
            .invokeMethod<String>('diagnose')
            .catchError((_) => null);
        if (diag != null && diag.isNotEmpty) {
          debugPrint('GStreamer diagnose:\n$diag');
        }

        final String? nextSource = nextSourceAfter(source, _sourceCandidates);
        if (nextSource != null) {
          debugPrint(
            missingElement
                ? 'Pipeline "$source" missing an element; trying "$nextSource"'
                : 'Pipeline "$source" failed; trying "$nextSource"',
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
        // Name every source tried; `e.message` is only the last failure.
        _errorMessage = shouldRetry
            ? 'No video source worked (tried: ${_sourceCandidates.join(', ')}). '
                  'Last error: ${e.message}'
            : 'Pipeline error: ${e.message}';
        _isPlaying = false;
      });
    }
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
    if (_usePluginPipeline) {
      channel
          .invokeMethod('stop')
          .catchError((e) => debugPrint('stop on dispose failed: $e'));
    }
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

    if (_useRustWebcam) {
      return _buildRustWebcamPage();
    }

    if (_usePluginPipeline) {
      return _buildNativeView();
    }

    // Fallback for other platforms: WebRTC stub view
    return _buildWebView();
  }

  Widget _buildRustWebcamPage() {
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
              _buildSectionTitle('Webcam Live Inference (Rust)'),
              RustWebcamView(width: textureWidth, height: textureHeight),
            ],
          ),
        ),
      ],
    );
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
                  settings: widget.webrtcSettings,
                  producerIdToConsume: null,
                ),
              ),
              const SizedBox(height: 20),
              const DetectionStatusLine(
                fetch: fetchHealthz,
                fallbackName: 'ObservANT',
                saveSettings: saveObservantSettings,
              ),
              const VisitStatsPanel(fetch: fetchVisits),
              const DevStatsPanel(
                fetch: fetchHealthz,
                playback: webrtc_import.playbackStats,
              ),
              const SizedBox(height: 20),
              const CameraPeers(fetchOwn: fetchHealthz, fetchFrom: fetchFrom),
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
      child: AspectRatio(aspectRatio: kWebRTCAspectRatio, child: child),
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
            settings: widget.webrtcSettings,
            producerIdToConsume: null,
          ),
        ),
      ],
    );
  }
}
