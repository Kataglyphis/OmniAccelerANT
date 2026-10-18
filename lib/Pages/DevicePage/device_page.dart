import 'package:anthology/Layout/ResponsiveDesign/single_page.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/app_attributes.dart';
import 'package:flutter/material.dart';
import 'package:omni_accelerant/Pages/DevicePage/esp32_controller.dart';
import 'package:omni_accelerant/src/rust/api/esp32.dart';

/// The ESP32-S3 companion: port, telemetry, the status LED and a manual ping. All
/// protocol work lives in Rust; this page is a view over [Esp32Controller].
class DevicePage extends StatefulWidget {
  const DevicePage({
    super.key,
    required this.appAttributes,
    required this.footer,
    this.controller,
  });

  final AppAttributes appAttributes;
  final Footer footer;

  /// Injected by widget tests; production owns its controller.
  final Esp32Controller? controller;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final Esp32Controller _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? Esp32Controller();
    _controller.refresh();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) =>
                    _DevicePanel(controller: _controller),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DevicePanel extends StatefulWidget {
  const _DevicePanel({required this.controller});

  final Esp32Controller controller;

  @override
  State<_DevicePanel> createState() => _DevicePanelState();
}

class _DevicePanelState extends State<_DevicePanel> {
  double _red = 0;
  double _green = 0;
  double _blue = 255;

  @override
  Widget build(BuildContext context) {
    final Esp32Controller controller = widget.controller;
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.usb),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ESP32-S3 companion',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                _StatusChip(controller: controller),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Rust owns the USB-serial protocol. The webcam pipeline reports '
              'detections to the board directly, so its LED reacts without a '
              'Dart round trip.',
              style: theme.textTheme.bodyMedium,
            ),
            const Divider(height: 32),
            if (!controller.available)
              _Notice(
                icon: Icons.desktop_windows_outlined,
                text:
                    'The ESP32 bridge is built for the desktop app (Linux and '
                    'Windows). Web and Android builds have no serial port.',
              )
            else ...<Widget>[
              _connectionRow(controller),
              if (controller.error != null) ...<Widget>[
                const SizedBox(height: 12),
                _Notice(icon: Icons.error_outline, text: controller.error!),
              ],
              if (controller.connected) ...<Widget>[
                const SizedBox(height: 24),
                _telemetry(theme, controller),
                const SizedBox(height: 24),
                _ledControls(controller),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectionRow(Esp32Controller controller) {
    final List<Esp32Device> devices = controller.devices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Serial port',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: controller.selectedPath,
                    isExpanded: true,
                    hint: Text(
                      devices.isEmpty
                          ? 'No serial port found'
                          : 'Select a port',
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final Esp32Device device in devices)
                        DropdownMenuItem<String>(
                          value: device.path,
                          child: Text(
                            _portLabel(device),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: controller.loading ? null : controller.select,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Rescan serial ports',
              onPressed: controller.loading ? null : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: controller.loading
                  ? null
                  : controller.connected
                  ? controller.disconnect
                  : controller.connect,
              icon: Icon(controller.connected ? Icons.link_off : Icons.link),
              label: Text(controller.connected ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          devices.isEmpty
              ? 'Attach the board with its USB port and rescan. The Espressif '
                    'USB JTAG/serial device appears as a CDC port.'
              : '${devices.where((Esp32Device d) => d.espressif).length} '
                    'Espressif board(s) of ${devices.length} serial port(s).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _telemetry(ThemeData theme, Esp32Controller controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Board', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 28,
          runSpacing: 12,
          children: <Widget>[
            _Info(label: 'Firmware', value: controller.firmware ?? '—'),
            _Info(label: 'MAC', value: controller.mac ?? '—'),
            _Info(label: 'Uptime', value: _formatUptime(controller.uptimeMs)),
            _Info(label: 'Free heap', value: _formatHeap(controller.freeHeap)),
            _Info(
              label: 'Chip temperature',
              value: _formatTemperature(controller.temperatureCentiC),
            ),
            _Info(
              label: 'BOOT button',
              value: controller.buttonDown ? 'held down' : 'released',
            ),
            _Info(
              label: 'Latest detections',
              value: '${controller.detectionCount}',
            ),
            if (controller.cameraSeen)
              _Info(
                label: 'On-device camera',
                value: controller.cameraDetections == 0
                    ? 'no hits yet'
                    : '${controller.cameraDetections} hit(s), '
                          '${(controller.cameraScorePermille / 10).toStringAsFixed(0)} %',
              ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.ping,
          icon: const Icon(Icons.network_ping),
          label: Text(
            controller.lastPong == 0
                ? 'Ping'
                : 'Ping (last id ${controller.lastPong})',
          ),
        ),
      ],
    );
  }

  Widget _ledControls(Esp32Controller controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Status LED', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color.fromARGB(
                  255,
                  _red.round(),
                  _green.round(),
                  _blue.round(),
                ),
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'GPIO2 on the board; colour is collapsed to on/off. A detection '
          'pulses it for 120–300 ms depending on the score.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _LedSlider(
          label: 'R',
          value: _red,
          color: Colors.red,
          onChanged: (double value) => setState(() => _red = value),
        ),
        _LedSlider(
          label: 'G',
          value: _green,
          color: Colors.green,
          onChanged: (double value) => setState(() => _green = value),
        ),
        _LedSlider(
          label: 'B',
          value: _blue,
          color: Colors.blue,
          onChanged: (double value) => setState(() => _blue = value),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton(
              onPressed: () => controller.setLed(
                _red.round(),
                _green.round(),
                _blue.round(),
              ),
              child: const Text('Apply'),
            ),
            OutlinedButton(
              onPressed: () => controller.setLed(
                _red.round(),
                _green.round(),
                _blue.round(),
                blinkMs: 500,
              ),
              child: const Text('Pulse 0.5 s'),
            ),
            TextButton(
              onPressed: () => controller.setLed(0, 0, 0),
              child: const Text('Off'),
            ),
          ],
        ),
      ],
    );
  }

  String _portLabel(Esp32Device device) {
    final String product =
        device.product ?? device.manufacturer ?? 'Serial port';
    final String mac = device.serialNumber ?? '';
    final String vendor = device.espressif ? 'ESP32 · ' : '';
    return '$vendor${device.path} · $product${mac.isEmpty ? '' : ' · $mac'}';
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _LedSlider extends StatelessWidget {
  const _LedSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 20,
          child: Text(label, style: TextStyle(color: color)),
        ),
        Expanded(
          child: Slider(
            value: value,
            max: 255,
            divisions: 255,
            label: '${value.round()}',
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${value.round()}', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.controller});

  final Esp32Controller controller;

  @override
  Widget build(BuildContext context) {
    final bool connected = controller.connected;
    final Color color = connected
        ? Colors.green
        : controller.error == null
        ? Colors.orange
        : Colors.red;
    final String label = connected
        ? 'Connected'
        : controller.loading
        ? 'Connecting…'
        : controller.error == null
        ? 'Disconnected'
        : 'Error';
    return Chip(
      avatar: Icon(Icons.circle, size: 12, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: colors.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: colors.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

String _formatUptime(int? milliseconds) {
  if (milliseconds == null) return '—';
  final int seconds = milliseconds ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final int minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String _formatHeap(int? bytes) {
  if (bytes == null || bytes == 0) return '—';
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}

String _formatTemperature(int? centiCelsius) {
  if (centiCelsius == null || centiCelsius == 0) return '—';
  return '${(centiCelsius / 100).toStringAsFixed(1)} °C';
}
