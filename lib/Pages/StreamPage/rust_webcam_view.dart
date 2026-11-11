import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// PlatformInt64Util: i64 is `int` natively and `BigInt` on web — AGENTS.md § 4.
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'package:omni_accelerant/src/rust/api/onnx.dart';
import 'package:omni_accelerant/src/rust/api/webcam.dart';

/// What the newest inference event said; empty while no session runs.
@immutable
class _Live {
  final List<DetectionBox> detections;
  final double fps;
  final double inferenceMs;

  /// The backend and execution provider the last session ran on.
  final String? provider;

  const _Live({
    this.detections = const <DetectionBox>[],
    this.fps = 0,
    this.inferenceMs = 0,
    this.provider,
  });

  /// No boxes and no rates, on the same provider.
  _Live cleared() => _Live(provider: provider);
}

/// Rust-driven webcam inference view; frames reach the [Texture] natively, only detections cross the bridge.
class RustWebcamView extends StatefulWidget {
  /// Capture/texture size.
  final int width;
  final int height;

  /// Class ids the stream reports at start; the class picker replaces them.
  final List<int> classes;

  /// A running session without an event for this long says so instead of showing its last numbers.
  static const Duration stallAfter = Duration(seconds: 5);

  const RustWebcamView({
    super.key,
    this.width = 1280,
    this.height = 720,
    this.classes = const <int>[0],
  });

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
  // A notifier, not setState: an event per inferred frame would rebuild the whole form.
  final ValueNotifier<_Live> _live = ValueNotifier<_Live>(const _Live());
  Timer? _stallTimer;
  bool _stalled = false;
  int _events = 0;

  late List<int> _classes = widget.classes;
  List<String> _labels = const [];

  bool _useTestSource = true;
  List<CameraDesc> _cameras = const [];
  int? _selectedCameraIndex;
  bool _listing = false;

  final TextEditingController _modelPathController = TextEditingController();
  double _scoreThreshold = 0.5;

  @override
  void initState() {
    super.initState();
    _createTexture();
    try {
      _labels = detectorLabels();
    } catch (e) {
      _error = 'Class names unavailable: $e';
    }
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

  Future<void> _refreshCameras() async {
    setState(() => _listing = true);
    try {
      final cameras = await listCameras();
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _error = cameras.isEmpty ? 'No camera found' : null;
        // A camera unplugged since the last listing is no selection any more.
        if (!cameras.any((c) => c.index == _selectedCameraIndex)) {
          _selectedCameraIndex = cameras.isEmpty ? null : cameras.first.index;
        }
        _useTestSource = cameras.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Camera enumeration failed: $e');
    } finally {
      if (mounted) setState(() => _listing = false);
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
        classes: Int64List.fromList(_classes),
        textureId: PlatformInt64Util.from(textureId),
      ),
    );
    _events = 0;
    _subscription = stream.listen(
      (event) {
        if (!mounted) return;
        _events++;
        _live.value = _Live(
          detections: event.detections,
          fps: event.fps,
          inferenceMs: event.inferenceMs,
          provider: '${event.backend} on ${event.executionProvider}',
        );
        _armStallTimer();
        if (_stalled) setState(() => _stalled = false);
      },
      onError: (Object e) {
        if (!mounted) return;
        _ended(error: '$e');
      },
      onDone: () {
        if (!mounted) return;
        // A start the core refused closes the stream without an event; its reason is in the log.
        _ended(
          error: _events == 0 && _error == null
              ? 'The session ended before its first frame; check the model and the camera'
              : _error,
        );
      },
    );
    _armStallTimer();
    setState(() {
      _running = true;
      _stalled = false;
      _error = null;
    });
  }

  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(RustWebcamView.stallAfter, () {
      if (!mounted || !_running) return;
      _live.value = _live.value.cleared();
      setState(() => _stalled = true);
    });
  }

  /// The session is over: no boxes or rates of it stay on screen beside "Stopped".
  void _ended({String? error}) {
    _stallTimer?.cancel();
    _live.value = _live.value.cleared();
    setState(() {
      _running = false;
      _stalled = false;
      _error = error;
    });
  }

  void _stop() {
    _release();
    if (_running) _ended(error: _error);
  }

  /// Stops the core's session and drops its stream, without touching the UI.
  void _release() {
    stopWebcamInference();
    _stallTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    // No setState from here: the element is already defunct, so _stop's rebuild failed an assertion.
    _release();
    _live.dispose();
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
                  // Its own layer: new boxes repaint the overlay, not the page around it.
                  RepaintBoundary(
                    child: ValueListenableBuilder<_Live>(
                      valueListenable: _live,
                      builder: (BuildContext context, _Live live, _) =>
                          CustomPaint(
                            painter: DetectionOverlayPainter(
                              detections: live.detections,
                              labels: _labels,
                              sourceWidth: widget.width.toDouble(),
                              sourceHeight: widget.height.toDouble(),
                            ),
                          ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStats() {
    final TextStyle style = TextStyle(
      fontWeight: FontWeight.bold,
      color: _running && !_stalled ? Colors.green : Colors.orange,
    );
    if (_stalled) {
      final int seconds = RustWebcamView.stallAfter.inSeconds;
      return Text('Running • no frames for $seconds s', style: style);
    }
    final String status = _running ? 'Running' : 'Stopped';
    return ValueListenableBuilder<_Live>(
      valueListenable: _live,
      builder: (BuildContext context, _Live live, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$status • ${live.fps.toStringAsFixed(1)} fps • '
            '${live.inferenceMs.toStringAsFixed(1)} ms inference • '
            '${live.detections.length} detection(s)',
            style: style,
          ),
          if (live.provider case final String provider)
            Text(provider, key: const ValueKey<String>('inferenceProvider')),
        ],
      ),
    );
  }

  Widget _buildClassPicker() {
    final int? selected = _classes.length == 1 ? _classes.single : null;
    return DropdownButton<int>(
      key: const ValueKey<String>('classPicker'),
      hint: Text('${_classes.length} classes'),
      value: selected != null && selected < _labels.length ? selected : null,
      items: [
        for (final (int id, String name) in _labels.indexed)
          DropdownMenuItem<int>(value: id, child: Text(name)),
      ],
      onChanged: _running
          ? null
          : (int? id) {
              if (id != null) setState(() => _classes = <int>[id]);
            },
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
                  if (!_listing) unawaited(_refreshCameras());
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
            _buildClassPicker(),
            IconButton(
              tooltip: 'Refresh cameras',
              icon: const Icon(Icons.refresh),
              // One device monitor at a time; a listing takes about a second.
              onPressed: _listing ? null : _refreshCameras,
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

  /// Class names by id, from `detectorLabels`; an unknown id shows as its number.
  final List<String> labels;
  final double sourceWidth;
  final double sourceHeight;

  DetectionOverlayPainter({
    required this.detections,
    this.labels = const <String>[],
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
          text:
              '${_label(det.classId.toInt())} ${(det.score * 100).toStringAsFixed(0)}%',
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

  String _label(int id) => id >= 0 && id < labels.length ? labels[id] : '$id';

  @override
  bool shouldRepaint(DetectionOverlayPainter oldDelegate) =>
      oldDelegate.detections != detections || oldDelegate.labels != labels;
}
