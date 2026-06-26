import 'package:flutter/material.dart';

import '../../domain/bidcdc_controller.dart';
import '../../domain/device_config.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.controller});

  final BidcdcController controller;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late final TextEditingController serialPort;
  late final TextEditingController baudRate;
  late final TextEditingController connectTimeoutMs;
  late final TextEditingController commandTimeoutMs;
  late final TextEditingController pollMs;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.config;
    serialPort = TextEditingController(text: config.serialPort);
    baudRate = TextEditingController(text: '${config.baudRate}');
    connectTimeoutMs =
        TextEditingController(text: '${config.connectTimeout.inMilliseconds}');
    commandTimeoutMs =
        TextEditingController(text: '${config.commandTimeout.inMilliseconds}');
    pollMs =
        TextEditingController(text: '${config.pollInterval.inMilliseconds}');
  }

  @override
  void dispose() {
    for (final controller in [
      serialPort,
      baudRate,
      connectTimeoutMs,
      commandTimeoutMs,
      pollMs
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return _Section(
      title: 'Connection',
      children: [
        Row(
          children: [
            Expanded(
                child: TextField(
                    controller: serialPort,
                    decoration:
                        const InputDecoration(labelText: 'Serial port'))),
            const SizedBox(width: 8),
            SizedBox(
                width: 116,
                child: TextField(
                    controller: baudRate,
                    decoration: const InputDecoration(labelText: 'Baud rate'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: TextField(
                    controller: connectTimeoutMs,
                    decoration:
                        const InputDecoration(labelText: 'Connect ms'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: commandTimeoutMs,
                    decoration:
                        const InputDecoration(labelText: 'Command ms'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: pollMs,
                    decoration: const InputDecoration(labelText: 'Poll ms'))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.save),
                label: const Text('Apply'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  _apply();
                  controller.connected
                      ? await controller.disconnect()
                      : await controller.connect();
                },
                icon: Icon(controller.connected ? Icons.link_off : Icons.link),
                label: Text(controller.connected ? 'Disconnect' : 'Connect'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _apply() {
    widget.controller.updateConfig(DeviceConfig(
      serialPort:
          serialPort.text.trim().isEmpty ? 'COM3' : serialPort.text.trim(),
      baudRate: int.tryParse(baudRate.text) ?? 115200,
      connectTimeout:
          Duration(milliseconds: int.tryParse(connectTimeoutMs.text) ?? 3000),
      commandTimeout:
          Duration(milliseconds: int.tryParse(commandTimeoutMs.text) ?? 600),
      pollInterval: Duration(milliseconds: int.tryParse(pollMs.text) ?? 100),
    ));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
