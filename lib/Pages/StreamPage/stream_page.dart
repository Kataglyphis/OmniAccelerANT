import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jotrockenmitlockenrepo/Pages/Footer/footer.dart';
import 'package:jotrockenmitlockenrepo/Layout/ResponsiveDesign/single_page.dart';
import 'package:jotrockenmitlockenrepo/app_attributes.dart';
import 'package:jotrockenmitlockenrepo/constants.dart';

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
  late final String _defaultNativeSource;
  late String _currentPipeline;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _isLinux => defaultTargetPlatform == TargetPlatform.linux;
  bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();

    _defaultNativeSource = _pickDefaultSource();
    _currentPipeline = _defaultNativeSource;

    // Native Integration für Desktop + Android initialisieren
    if (!kIsWeb && (_isWindows || _isLinux || _isMacOS || _isAndroid)) {
      _initializeNative();
    }
  }

  String _pickDefaultSource() {
    if (_isWindows) return 'ksvideosrc';
    if (_isLinux) return 'v4l2src';
    if (_isMacOS) return 'avfvideosrc';
    return 'videotestsrc';
  }

  void _initializeNative() {
    textureId = channel
        .invokeMethod<int>('create', <int>[textureWidth, textureHeight])
        .then((id) {
          _setPipeline(_buildPipelineString(_defaultNativeSource));
          return id;
        })
        .catchError((e) {
          debugPrint('create texture error: $e');
          setState(() {
            _errorMessage = 'Texture creation failed: $e';
          });
          throw e;
        });
  }

  String _buildPipelineString(String source) {
    switch (source) {
      case 'videotestsrc':
        return 'videotestsrc pattern=ball ! videoconvert ! video/x-raw,format=RGBA,width=$textureWidth,height=$textureHeight,framerate=30/1 ! appsink name=sink emit-signals=true sync=false';
      case 'v4l2src':
        return 'v4l2src device=/dev/video0 ! image/jpeg,width=$textureWidth,height=$textureHeight,framerate=30/1 ! jpegdec ! videoconvert ! video/x-raw,format=RGBA,width=$textureWidth,height=$textureHeight ! appsink name=sink emit-signals=true sync=false';
      case 'ksvideosrc':
        return 'ksvideosrc device-index=0 ! videoconvert ! video/x-raw,format=RGBA,width=$textureWidth,height=$textureHeight,framerate=30/1 ! appsink name=sink emit-signals=true sync=false';
      case 'avfvideosrc':
        return 'avfvideosrc capture-raw-data=true ! videoconvert ! video/x-raw,format=RGBA,width=$textureWidth,height=$textureHeight,framerate=30/1 ! appsink name=sink emit-signals=true sync=false';
      case 'pattern-smpte':
        return 'videotestsrc pattern=smpte ! videoconvert ! video/x-raw,format=RGBA,width=$textureWidth,height=$textureHeight,framerate=30/1 ! appsink name=sink emit-signals=true sync=false';
      case 'pattern-snow':
        return 'videotestsrc pattern=snow ! videoconvert ! video/x-raw,format=RGBA,width=$textureWidth,height=$textureHeight,framerate=30/1 ! appsink name=sink emit-signals=true sync=false';
      default:
        return 'videotestsrc pattern=ball ! videoconvert ! video/x-raw,format=RGBA,width=$textureWidth,height=$textureHeight,framerate=30/1 ! appsink name=sink emit-signals=true sync=false';
    }
  }

  Future<void> _setPipeline(String pipelineString) async {
    try {
      setState(() {
        _errorMessage = null;
      });

      if (_isPlaying) {
        await channel.invokeMethod('stop');
      }

      await channel.invokeMethod('setPipeline', pipelineString);
      await channel.invokeMethod('play');

      setState(() {
        _isPlaying = true;
      });

      debugPrint('Pipeline set and playing: $pipelineString');
    } on PlatformException catch (e) {
      debugPrint('setPipeline failed: $e');
      setState(() {
        _errorMessage = 'Pipeline error: ${e.message}';
        _isPlaying = false;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await channel.invokeMethod('pause');
        setState(() {
          _isPlaying = false;
        });
      } else {
        await channel.invokeMethod('play');
        setState(() {
          _isPlaying = true;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('togglePlayPause failed: $e');
      setState(() {
        _errorMessage = 'Play/Pause error: ${e.message}';
      });
    }
  }

  Future<void> _stopPipeline() async {
    try {
      await channel.invokeMethod('stop');
      setState(() {
        _isPlaying = false;
      });
    } on PlatformException catch (e) {
      debugPrint('stop failed: $e');
    }
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
                  color: Colors.red.withOpacity(0.1),
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
                      width: textureWidth.toDouble(),
                      height: textureHeight.toDouble(),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return SizedBox(
                      width: textureWidth.toDouble(),
                      height: textureHeight.toDouble(),
                      child: Center(child: Text('Error: ${snapshot.error}')),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data == null) {
                    return const Text('Error creating texture (null id)');
                  }

                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey, width: 2),
                    ),
                    child: SizedBox(
                      width: textureWidth.toDouble(),
                      height: textureHeight.toDouble(),
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
                  OutlinedButton.icon(
                    icon: const Icon(Icons.sports_soccer),
                    label: const Text('Test Pattern (Ball)'),
                    onPressed: () {
                      _currentPipeline = 'videotestsrc';
                      _setPipeline(_buildPipelineString('videotestsrc'));
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.grid_on),
                    label: const Text('SMPTE Pattern'),
                    onPressed: () {
                      _currentPipeline = 'pattern-smpte';
                      _setPipeline(_buildPipelineString('pattern-smpte'));
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.grain),
                    label: const Text('Snow Pattern'),
                    onPressed: () {
                      _currentPipeline = 'pattern-snow';
                      _setPipeline(_buildPipelineString('pattern-snow'));
                    },
                  ),
                  if (_isWindows)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Windows Camera (ksvideosrc)'),
                      onPressed: () {
                        _currentPipeline = 'ksvideosrc';
                        _setPipeline(_buildPipelineString('ksvideosrc'));
                      },
                    ),
                  if (_isLinux)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Webcam (/dev/video0)'),
                      onPressed: () {
                        _currentPipeline = 'v4l2src';
                        _setPipeline(_buildPipelineString('v4l2src'));
                      },
                    ),
                  if (_isMacOS)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text('Mac Camera (avfvideosrc)'),
                      onPressed: () {
                        _currentPipeline = 'avfvideosrc';
                        _setPipeline(_buildPipelineString('avfvideosrc'));
                      },
                    ),
                ],
              ),

              const Divider(),
              const Text(
                'Static Colors (Legacy)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              // Color buttons
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
          ),
        ),
      ],
    );
  }
}
