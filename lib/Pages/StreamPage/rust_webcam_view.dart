import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// PlatformInt64Util: i64 is `int` natively and `BigInt` on web — AGENTS.md § 3.
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'package:omni_accelerant/src/rust/api/webcam.dart';

/// Windows webcam live-inference view, fully driven by Rust.
///
/// The Rust engine owns the GStreamer capture pipeline and ONNX inference;
/// video frames go straight from Rust into the native plugin's Flutter
/// texture (`knt_push_frame` C ABI) and never cross the Dart bridge. Only
/// detection metadata arrives here (as a stream) and is painted as an
/// overlay on top of the [Texture].
class RustWebcamView extends StatefulWidget {
  /// Capture/texture size.
  final int width;
  final int height;

  const RustWebcamView({super.key, this.width = 1280, this.height = 720});

  @override
  State<RustWebcamView> createState() => _RustWebcamViewState();
}

class _RustWebcamViewState extends State<RustWebcamView> {
  static const MethodChannel _channel = MethodChannel(
    'kataglyphis_native_inference',
  );

  int? _textureId;
  String? _error;
  bool _running = false;

  StreamSubscription<DetectionEvent>? _subscription;
  List<DetectionBox> _detections = const [];
  double _fps = 0;
  double _inferenceMs = 0;

  bool _useTestSource = true;
  List<CameraDesc> _cameras = const [];
  int? _selectedCameraIndex;

  final TextEditingController _modelPathController = TextEditingController();
  double _scoreThreshold = 0.5;

  @override
  void initState() {
    super.initState();
    _createTexture();
  }

  Future<void> _createTexture() async {
    try {
      final int? id = await _channel.invokeMethod<int>('create', <int>[
        widget.width,
        widget.height,
      ]);
      if (!mounted) return;
      setState(() => _textureId = id);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Texture creation failed: ${e.message}');
    }
  }

  void _refreshCameras() {
    try {
      final cameras = listCameras();
      setState(() {
        _cameras = cameras;
        _error = null;
        if (cameras.isNotEmpty) {
          _selectedCameraIndex ??= cameras.first.index;
          _useTestSource = false;
        }
      });
    } catch (e) {
      setState(() => _error = 'Camera enumeration failed: $e');
    }
  }

  void _start() {
    final int? textureId = _textureId;
    if (textureId == null) {
      setState(() => _error = 'No texture yet — cannot start');
      return;
    }
    _stop();

    final stream = startWebcamInference(
      config: WebcamStreamConfig(
        useTestSource: _useTestSource,
        deviceIndex: _useTestSource ? null : _selectedCameraIndex,
        width: widget.width,
        height: widget.height,
        framerate: 30,
        modelPath: _modelPathController.text.trim(),
        scoreThreshold: _scoreThreshold,
        textureId: PlatformInt64Util.from(textureId),
      ),
    );
    _subscription = stream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _detections = event.detections;
          _fps = event.fps;
          _inferenceMs = event.inferenceMs;
          _error = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = '$e';
          _running = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _running = false);
      },
    );
    setState(() {
      _running = true;
      _error = null;
      _detections = const [];
    });
  }

  void _stop() {
    stopWebcamInference();
    _subscription?.cancel();
    _subscription = null;
    if (mounted && _running) {
      setState(() => _running = false);
    } else {
      _running = false;
    }
  }

  @override
  void dispose() {
    _stop();
    _modelPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.red.withValues(alpha: 0.1),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        _buildVideoArea(),
        const SizedBox(height: 8),
        _buildStats(),
        const SizedBox(height: 8),
        _buildControls(),
      ],
    );
  }

  Widget _buildVideoArea() {
    final double aspect = widget.width / widget.height;
    return Container(
      constraints: const BoxConstraints(maxWidth: 960),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
      child: AspectRatio(
        aspectRatio: aspect,
        child: _textureId == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                fit: StackFit.expand,
                children: [
                  Texture(textureId: _textureId!),
                  CustomPaint(
                    painter: DetectionOverlayPainter(
                      detections: _detections,
                      sourceWidth: widget.width.toDouble(),
                      sourceHeight: widget.height.toDouble(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStats() {
    final String status = _running ? 'Running' : 'Stopped';
    return Text(
      '$status • ${_fps.toStringAsFixed(1)} fps • '
      '${_inferenceMs.toStringAsFixed(1)} ms inference • '
      '${_detections.length} detection(s)',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: _running ? Colors.green : Colors.orange,
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Test pattern'),
              selected: _useTestSource,
              onSelected: (v) => setState(() => _useTestSource = true),
            ),
            ChoiceChip(
              label: const Text('Webcam'),
              selected: !_useTestSource,
              onSelected: (v) {
                if (_cameras.isEmpty) {
                  _refreshCameras();
                } else {
                  setState(() => _useTestSource = false);
                }
              },
            ),
            if (!_useTestSource && _cameras.isNotEmpty)
              DropdownButton<int>(
                value: _selectedCameraIndex,
                items: _cameras
                    .map(
                      (c) => DropdownMenuItem<int>(
                        value: c.index,
                        child: Text('${c.index}: ${c.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCameraIndex = v),
              ),
            IconButton(
              tooltip: 'Refresh cameras',
              icon: const Icon(Icons.refresh),
              onPressed: _refreshCameras,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: TextField(
            controller: _modelPathController,
            decoration: const InputDecoration(
              labelText: 'ONNX model path',
              hintText: 'empty = default model resolution',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Threshold'),
            SizedBox(
              width: 200,
              child: Slider(
                value: _scoreThreshold,
                min: 0.05,
                max: 0.95,
                divisions: 18,
                label: _scoreThreshold.toStringAsFixed(2),
                onChanged: (v) => setState(() => _scoreThreshold = v),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
              onPressed: _running ? null : _start,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              onPressed: _running ? _stop : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Paints detection boxes (source-pixel coordinates) scaled onto the widget.
class DetectionOverlayPainter extends CustomPainter {
  final List<DetectionBox> detections;
  final double sourceWidth;
  final double sourceHeight;

  DetectionOverlayPainter({
    required this.detections,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;
    final double scaleX = size.width / sourceWidth;
    final double scaleY = size.height / sourceHeight;

    final Paint boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.greenAccent;

    for (final det in detections) {
      final rect = Rect.fromLTRB(
        det.x1 * scaleX,
        det.y1 * scaleY,
        det.x2 * scaleX,
        det.y2 * scaleY,
      );
      canvas.drawRect(rect, boxPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${(det.score * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            backgroundColor: Colors.greenAccent,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          rect.left,
          (rect.top - textPainter.height).clamp(0, size.height),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(DetectionOverlayPainter oldDelegate) =>
      oldDelegate.detections != detections;
}
