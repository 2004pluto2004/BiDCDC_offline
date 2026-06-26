import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/protocol/models.dart';
import '../../domain/bidcdc_controller.dart';
import '../../domain/device_config.dart';

enum _DashboardTab { overview, calibration }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.controller});

  final BidcdcController controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final TextEditingController serialPort;
  late final TextEditingController baudRate;
  late final TextEditingController setpoint;
  _DashboardTab selectedTab = _DashboardTab.overview;
  PowerDirection direction = PowerDirection.leftToRight;
  RunMode mode = RunMode.cv;
  bool fan = false;
  double cvSetpoint = 2;
  double ccSetpoint = 1;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.config;
    serialPort = TextEditingController(text: config.serialPort);
    baudRate = TextEditingController(text: '${config.baudRate}');
    setpoint = TextEditingController(text: '2.00');
  }

  @override
  void dispose() {
    serialPort.dispose();
    baudRate.dispose();
    setpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _Colors.bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 980;
                return Column(
                  children: [
                    _TopBar(
                      controller: widget.controller,
                      serialPort: serialPort,
                      baudRate: baudRate,
                      onApplyConnection: _applyConnection,
                      onToggleConnection: _toggleConnection,
                    ),
                    Expanded(
                      child: compact
                          ? _CompactBody(
                              controller: widget.controller,
                              setpoint: setpoint,
                              pdEnabled: mode == RunMode.cv,
                              onPdSetpoint: _setOuterLoopSet,
                              controlPanel: _ControlDeck(
                                controller: widget.controller,
                                setpoint: setpoint,
                                mode: mode,
                                direction: direction,
                                fan: fan,
                                canConfigure: _canConfigure,
                                onModeChanged: _setMode,
                                onDirectionChanged: _setDirection,
                                onFanChanged: _setFan,
                                onSetpoint: _setOuterLoopSet,
                                onRun: _run,
                                onStop: _stop,
                                onReadBack: _readBack,
                              ),
                            )
                          : Row(
                              children: [
                                _NavigationRail(
                                  selected: selectedTab,
                                  onChanged: (tab) =>
                                      setState(() => selectedTab = tab),
                                ),
                                Expanded(
                                  child: _CenterDeck(
                                    controller: widget.controller,
                                    setpoint: setpoint,
                                    pdEnabled: mode == RunMode.cv,
                                    onPdSetpoint: _setOuterLoopSet,
                                    selectedTab: selectedTab,
                                    controlPanel: _ControlDeck(
                                      controller: widget.controller,
                                      setpoint: setpoint,
                                      mode: mode,
                                      direction: direction,
                                      fan: fan,
                                      canConfigure: _canConfigure,
                                      onModeChanged: _setMode,
                                      onDirectionChanged: _setDirection,
                                      onFanChanged: _setFan,
                                      onSetpoint: _setOuterLoopSet,
                                      onRun: _run,
                                      onStop: _stop,
                                      onReadBack: _readBack,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 260,
                                  child:
                                      _RightDeck(controller: widget.controller),
                                ),
                              ],
                            ),
                    ),
                    _BottomStatusBar(controller: widget.controller),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _applyConnection() {
    widget.controller.updateConfig(DeviceConfig(
      serialPort:
          serialPort.text.trim().isEmpty ? 'COM3' : serialPort.text.trim(),
      baudRate: int.tryParse(baudRate.text) ?? 115200,
      connectTimeout: widget.controller.config.connectTimeout,
      commandTimeout: widget.controller.config.commandTimeout,
      pollInterval: widget.controller.config.pollInterval,
    ));
  }

  Future<void> _toggleConnection() async {
    _applyConnection();
    if (widget.controller.connected) {
      await widget.controller.disconnect();
      return;
    }
    await widget.controller.connect();
    final status = widget.controller.status;
    if (status != null) _syncControlsFromStatus(status);
  }

  Future<void> _readBack() async {
    await widget.controller.refreshAll();
    final status = widget.controller.status;
    if (status != null) _syncControlsFromStatus(status);
  }

  Future<void> _stop() async {
    await widget.controller.stop();
    final status = widget.controller.status;
    if (status != null &&
        status.command == SystemCommand.idle.id &&
        status.state == SystemCommand.idle.id) {
      _syncControlsFromStatus(status);
    }
  }

  void _syncControlsFromStatus(DeviceStatus status) {
    direction = status.direction == PowerDirection.rightToLeft.id
        ? PowerDirection.rightToLeft
        : PowerDirection.leftToRight;
    mode = status.runMode == RunMode.cc.id ? RunMode.cc : RunMode.cv;
    if (mode == RunMode.cv) {
      cvSetpoint = status.outerLoopSet;
    } else {
      ccSetpoint = status.outerLoopSet;
    }
    setpoint.text = status.outerLoopSet.toStringAsFixed(2);
    fan = status.fanEnabled;
    if (mounted) setState(() {});
  }

  bool get _canConfigure {
    final status = widget.controller.status;
    return widget.controller.connected &&
        status != null &&
        status.command == SystemCommand.idle.id &&
        status.state == SystemCommand.idle.id;
  }

  void _setMode(RunMode value) {
    if (!_canConfigure || value == mode) return;
    unawaited(_applyMode(value));
  }

  Future<void> _applyMode(RunMode value) async {
    final target = value == RunMode.cv ? cvSetpoint : ccSetpoint;
    await widget.controller.setModeAndSetpoint(value, target);
    final status = widget.controller.status;
    if (status != null) _syncControlsFromStatus(status);
  }

  void _setDirection(PowerDirection value) {
    if (!_canConfigure) return;
    unawaited(_applyDirection(value));
  }

  Future<void> _applyDirection(PowerDirection value) async {
    await widget.controller.setDirection(value);
    final status = widget.controller.status;
    if (status != null) _syncControlsFromStatus(status);
  }

  void _setFan(bool value) {
    unawaited(_applyFan(value));
  }

  Future<void> _applyFan(bool value) async {
    await widget.controller.setFan(value);
    final status = widget.controller.status;
    if (status != null) _syncControlsFromStatus(status);
  }

  Future<void> _setOuterLoopSet(double value) async {
    final min = mode == RunMode.cv ? 2.0 : 0.1;
    final max = mode == RunMode.cv ? 50.0 : 5.0;
    final normalized = value.clamp(min, max).toDouble();
    if (mode == RunMode.cv) {
      cvSetpoint = normalized;
    } else {
      ccSetpoint = normalized;
    }
    setpoint.text = normalized.toStringAsFixed(2);
    await widget.controller.setOuterLoopSet(normalized);
  }

  Future<void> _run() async {
    final fallback = mode == RunMode.cv ? cvSetpoint : ccSetpoint;
    final value = double.tryParse(setpoint.text) ?? fallback;
    await widget.controller.run(direction, mode, value);
    final status = widget.controller.status;
    if (status != null) _syncControlsFromStatus(status);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.serialPort,
    required this.baudRate,
    required this.onApplyConnection,
    required this.onToggleConnection,
  });

  final BidcdcController controller;
  final TextEditingController serialPort;
  final TextEditingController baudRate;
  final VoidCallback onApplyConnection;
  final Future<void> Function() onToggleConnection;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _Colors.panel,
        border: Border(bottom: BorderSide(color: _Colors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _Colors.blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _Colors.cyan),
            ),
            child: const Icon(Icons.bolt, color: _Colors.cyan),
          ),
          const SizedBox(width: 12),
          const Text(
            '双向升降压电源上位机',
            style: TextStyle(
              color: _Colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 18),
          _TopMeta(label: '版本', value: 'v0.3.1'),
          const SizedBox(width: 18),
          _TopMeta(label: '设备型号', value: 'STM32F407 控制'),
          const Spacer(),
          _ConnectionDot(connected: controller.connected),
          const SizedBox(width: 18),
          SizedBox(
            width: 92,
            child: _DarkField(controller: serialPort, label: 'COM'),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: _DarkField(controller: baudRate, label: 'Baud'),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Apply connection settings',
            child: IconButton(
              onPressed: onApplyConnection,
              icon: const Icon(Icons.save_outlined),
            ),
          ),
          FilledButton.icon(
            onPressed: onToggleConnection,
            icon: Icon(controller.connected ? Icons.link_off : Icons.usb),
            label: Text(controller.connected ? '断开' : '连接'),
          ),
        ],
      ),
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({required this.selected, required this.onChanged});

  final _DashboardTab selected;
  final ValueChanged<_DashboardTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: _Colors.sidebar,
        border: Border(right: BorderSide(color: _Colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavItem(
            icon: Icons.home,
            label: '总览',
            selected: selected == _DashboardTab.overview,
            onTap: () => onChanged(_DashboardTab.overview),
          ),
          _NavItem(
            icon: Icons.science_outlined,
            label: '校准',
            selected: selected == _DashboardTab.calibration,
            onTap: () => onChanged(_DashboardTab.calibration),
          ),
          const _NavItem(icon: Icons.tune, label: '参数设置'),
          const _NavItem(icon: Icons.air, label: '风扇控制'),
          const _NavItem(icon: Icons.security, label: '保护参数'),
          const _NavItem(icon: Icons.article_outlined, label: '运行日志'),
          const Spacer(),
          const _DevicePlate(),
        ],
      ),
    );
  }
}

class _CenterDeck extends StatelessWidget {
  const _CenterDeck({
    required this.controller,
    required this.setpoint,
    required this.pdEnabled,
    required this.onPdSetpoint,
    required this.selectedTab,
    required this.controlPanel,
  });

  final BidcdcController controller;
  final TextEditingController setpoint;
  final bool pdEnabled;
  final Future<void> Function(double value) onPdSetpoint;
  final _DashboardTab selectedTab;
  final Widget controlPanel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: selectedTab == _DashboardTab.overview
            ? [
                _MetricGrid(controller: controller),
                const SizedBox(height: 10),
                controlPanel,
                const SizedBox(height: 10),
                Expanded(
                  child: _PdPresetPanel(
                    controller: controller,
                    setpoint: setpoint,
                    enabled: pdEnabled,
                    onSetpoint: onPdSetpoint,
                  ),
                ),
              ]
            : [
                Expanded(child: _CalibrationPage(controller: controller)),
              ],
      ),
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({
    required this.controller,
    required this.setpoint,
    required this.pdEnabled,
    required this.onPdSetpoint,
    required this.controlPanel,
  });

  final BidcdcController controller;
  final TextEditingController setpoint;
  final bool pdEnabled;
  final Future<void> Function(double value) onPdSetpoint;
  final Widget controlPanel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _MetricGrid(controller: controller),
        const SizedBox(height: 10),
        controlPanel,
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: _PdPresetPanel(
            controller: controller,
            setpoint: setpoint,
            enabled: pdEnabled,
            onSetpoint: onPdSetpoint,
          ),
        ),
        const SizedBox(height: 10),
        _RightDeck(controller: controller),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.controller});

  final BidcdcController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    final liveMetric = s == null ? null : MetricSample.fromStatus(s);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 640 ? 2 : 4;
        final itemWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        final cards = [
          _MetricCard(
            title: '输入电压',
            value: liveMetric?.inputVoltage ?? 0,
            unit: 'V',
            range: '15 ~ 32 V',
            color: _Colors.cyan,
            values: [
              for (final sample in controller.metricHistory)
                sample.inputVoltage,
            ],
          ),
          _MetricCard(
            title: '输出电压',
            value: liveMetric?.outputVoltage ?? 0,
            unit: 'V',
            range: '2 ~ 50 V',
            color: _Colors.blue,
            values: [
              for (final sample in controller.metricHistory)
                sample.outputVoltage,
            ],
          ),
          _MetricCard(
            title: '输出电流',
            value: liveMetric?.outputCurrent ?? 0,
            unit: 'A',
            range: '0 ~ 5.00 A',
            color: _Colors.cyan,
            values: [
              for (final sample in controller.metricHistory)
                sample.outputCurrent,
            ],
          ),
          _MetricCard(
            title: '输出功率',
            value: liveMetric?.outputPower ?? 0,
            unit: 'W',
            range: '0 ~ 250 W',
            color: _Colors.blue,
            values: [
              for (final sample in controller.metricHistory) sample.outputPower,
            ],
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _ControlDeck extends StatelessWidget {
  const _ControlDeck({
    required this.controller,
    required this.setpoint,
    required this.mode,
    required this.direction,
    required this.fan,
    required this.canConfigure,
    required this.onModeChanged,
    required this.onDirectionChanged,
    required this.onFanChanged,
    required this.onSetpoint,
    required this.onRun,
    required this.onStop,
    required this.onReadBack,
  });

  final BidcdcController controller;
  final TextEditingController setpoint;
  final RunMode mode;
  final PowerDirection direction;
  final bool fan;
  final bool canConfigure;
  final ValueChanged<RunMode> onModeChanged;
  final ValueChanged<PowerDirection> onDirectionChanged;
  final ValueChanged<bool> onFanChanged;
  final Future<void> Function(double value) onSetpoint;
  final Future<void> Function() onRun;
  final Future<void> Function() onStop;
  final Future<void> Function() onReadBack;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '核心控制',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final children = [
                _ModeCard(
                  mode: mode,
                  enabled: canConfigure,
                  onChanged: onModeChanged,
                ),
                _SetpointCard(
                  index: 2,
                  title: mode == RunMode.cv ? '输出电压设定 (V)' : '输出电流设定 (A)',
                  controller: setpoint,
                  min: mode == RunMode.cv ? 2 : 0.1,
                  max: mode == RunMode.cv ? 50 : 5,
                  enabled: controller.connected,
                  onSubmit: onSetpoint,
                ),
                _FanCard(fan: fan, onChanged: onFanChanged),
                _DirectionCard(
                  direction: direction,
                  enabled: canConfigure,
                  onChanged: onDirectionChanged,
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    for (final child in children) ...[
                      child,
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    Expanded(child: children[i]),
                    if (i != children.length - 1) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _Colors.green.withValues(alpha: 0.28),
                    foregroundColor: _Colors.green,
                    side: const BorderSide(color: _Colors.green),
                  ),
                  onPressed: canConfigure ? onRun : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('启动输出'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _Colors.red.withValues(alpha: 0.22),
                    foregroundColor: _Colors.red,
                    side: const BorderSide(color: _Colors.red),
                  ),
                  onPressed: controller.connected ? onStop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止输出'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: controller.resetFault,
                tooltip: '一键复位',
                icon: const Icon(Icons.lock_reset),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onReadBack,
                tooltip: 'ReadBack',
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PdPresetPanel extends StatelessWidget {
  const _PdPresetPanel({
    required this.controller,
    required this.setpoint,
    required this.enabled,
    required this.onSetpoint,
  });

  final BidcdcController controller;
  final TextEditingController setpoint;
  final bool enabled;
  final Future<void> Function(double value) onSetpoint;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'PD 多档电压预设',
      expandChild: true,
      trailing: Text(
        enabled ? '点击档位写入 CV 外环设定' : 'CC 模式下不可用',
        style: const TextStyle(color: _Colors.muted, fontSize: 12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760
              ? 4
              : constraints.maxWidth >= 520
                  ? 3
                  : 2;
          const spacing = 8.0;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final preset in _pdPresets)
                SizedBox(
                  width: width,
                  child: _PdPresetTile(
                    preset: preset,
                    selected: ((controller.status?.outerLoopSet ?? -1) -
                                preset.voltage)
                            .abs() <
                        0.05,
                    onTap: enabled
                        ? () async {
                            setpoint.text = preset.voltage.toStringAsFixed(2);
                            await onSetpoint(preset.voltage);
                          }
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CalibrationPage extends StatelessWidget {
  const _CalibrationPage({required this.controller});

  final BidcdcController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final adcCodes = status?.adcCodes ?? const <double>[];
    final codes = controller.calibrationCodes;
    return _Panel(
      title: '校准',
      expandChild: true,
      trailing: FilledButton.icon(
        onPressed: () async {
          await controller.readStatus();
          await controller.readCalibrationCodes();
        },
        icon: const Icon(Icons.refresh),
        label: const Text('读取 Code'),
      ),
      child: ListView(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CalibrationValueCard(
                title: 'UL 电压 ADC',
                value: codes?.ulCode,
                fallback: adcCodes.isNotEmpty ? adcCodes[0] : null,
                unit: 'code',
                color: _Colors.cyan,
              ),
              _CalibrationValueCard(
                title: 'UR 电压 ADC',
                value: codes?.urCode,
                fallback: adcCodes.length > 1 ? adcCodes[1] : null,
                unit: 'code',
                color: _Colors.blue,
              ),
              _CalibrationValueCard(
                title: 'IL 电流 ADC',
                value: codes?.ilCode,
                fallback: adcCodes.length > 2 ? adcCodes[2] : null,
                unit: 'code',
                color: _Colors.green,
              ),
              _CalibrationValueCard(
                title: 'LIO 电流 ADC',
                value: codes?.lioCode,
                fallback: adcCodes.length > 3 ? adcCodes[3] : null,
                unit: 'code',
                color: _Colors.blue,
              ),
              _CalibrationValueCard(
                title: 'RIO 电流 ADC',
                value: codes?.rioCode,
                fallback: adcCodes.length > 4 ? adcCodes[4] : null,
                unit: 'code',
                color: _Colors.cyan,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _CalibrationHintPanel(),
          const SizedBox(height: 12),
          _CalibrationInfoPanel(status: status),
        ],
      ),
    );
  }
}

class _CalibrationValueCard extends StatelessWidget {
  const _CalibrationValueCard({
    required this.title,
    required this.value,
    required this.fallback,
    required this.unit,
    required this.color,
  });

  final String title;
  final double? value;
  final double? fallback;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final shown = value ?? fallback;
    return Container(
      width: 180,
      height: 96,
      padding: const EdgeInsets.all(12),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: _Colors.muted, fontSize: 12)),
          const Spacer(),
          Text(
            shown == null ? '--' : shown.toStringAsFixed(2),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(unit,
              style: const TextStyle(color: _Colors.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _CalibrationHintPanel extends StatelessWidget {
  const _CalibrationHintPanel();

  @override
  Widget build(BuildContext context) {
    const lines = [
      '总览电压/电流来自固件 Meter.Value[]，已经经过 K/B 校准。',
      'ADC Code 来自 Meter.NewAdcCode[]，是未校准原始采样值。',
      'L2R：输入校准看 UL，输出电压看 UR，输出电流/功率看 RIO；R2L 时左右互换，输出电流/功率看 LIO。',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _Colors.inner,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _Colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines) ...[
            Text(
              line,
              style: const TextStyle(
                color: _Colors.muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            if (line != lines.last) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _CalibrationInfoPanel extends StatelessWidget {
  const _CalibrationInfoPanel({required this.status});

  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '测量值参考',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MiniReadout(
              'UL', '${(status?.leftVoltage ?? 0).toStringAsFixed(2)} V'),
          _MiniReadout(
              'UR', '${(status?.rightVoltage ?? 0).toStringAsFixed(2)} V'),
          _MiniReadout(
              'IL', '${(status?.inductorCurrent ?? 0).toStringAsFixed(2)} A'),
          _MiniReadout('LIO',
              '${(status?.leftInputOutputCurrent ?? 0).toStringAsFixed(2)} A'),
          _MiniReadout('RIO',
              '${(status?.rightInputOutputCurrent ?? 0).toStringAsFixed(2)} A'),
          const _MiniReadout('电压 Code 命令', '03 FF 41'),
          const _MiniReadout('电流 Code 命令', '04 BE 83'),
        ],
      ),
    );
  }
}

class _MiniReadout extends StatelessWidget {
  const _MiniReadout(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _Colors.inner,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _Colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _Colors.muted, fontSize: 12)),
          ),
          Text(value,
              style: const TextStyle(
                  color: _Colors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

const _pdPresets = [
  _PdPreset(5, '普通低压设备'),
  _PdPreset(9, '快充设备'),
  _PdPreset(12, '小功率直流设备'),
  _PdPreset(15, 'PD 常用电压'),
  _PdPreset(20, '笔记本供电'),
  _PdPreset(28, 'PD3.1 EPR 档位'),
  _PdPreset(36, 'PD3.1 EPR 档位'),
  _PdPreset(48, 'PD3.1 EPR 高压档位'),
];

class _PdPreset {
  const _PdPreset(this.voltage, this.description);

  final double voltage;
  final String description;
}

class _RightDeck extends StatelessWidget {
  const _RightDeck({required this.controller});

  final BidcdcController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    final info = controller.deviceInfo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: Column(
        children: [
          _Panel(
            title: '设备状态',
            child: Column(
              children: [
                _StatusLine(
                  icon: Icons.verified_user_outlined,
                  label: controller.connected ? '运行正常' : '设备离线',
                  value: controller.connected ? '正常' : 'Offline',
                  color: controller.connected ? _Colors.green : _Colors.red,
                ),
                _StatusLine(
                  icon: Icons.thermostat,
                  label: '系统温度',
                  value: '正常',
                  color: _Colors.green,
                ),
                _StatusLine(
                  icon: Icons.air,
                  label: '散热风扇',
                  value: (s?.fanEnabled ?? false) ? 'ON' : 'OFF',
                  color: _Colors.blue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Panel(
            title: '保护状态',
            child: Column(
              children: [
                _ProtectionRow('过压保护', s?.faultCode == 0),
                _ProtectionRow('过流保护', s?.faultCode == 0),
                _ProtectionRow('过温保护', s?.faultCode == 0),
                _ProtectionRow('短路保护', s?.faultCode == 0),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Panel(
            title: '系统信息',
            child: Column(
              children: [
                const _InfoRow('硬件版本', 'STM32F407'),
                _InfoRow('固件版本',
                    info == null ? '--' : 'CV_CC ${info.firmwareVersion}'),
                _InfoRow('协议版本',
                    info == null ? '--' : 'BDC2 ${info.protocolVersion}'),
                const _InfoRow('上位机版本', 'v0.3.1'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _Panel(
              title: '告警信息',
              child: Text(
                s?.faultCode == 0 ? '无告警' : 'Fault ${s?.faultCode}',
                style: TextStyle(
                  color: s?.faultCode == 0 ? _Colors.green : _Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.range,
    required this.color,
    required this.values,
  });

  final String title;
  final double value;
  final String unit;
  final String range;
  final Color color;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(10),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: _Colors.text, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value.toStringAsFixed(unit == 'W' ? 1 : 2),
                    style: TextStyle(
                      color: color,
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(unit, style: TextStyle(color: color, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: CustomPaint(
              painter: _SparklinePainter(
                values: values.takeLast(48).toList(),
                color: color,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 4),
          Text(range,
              style: const TextStyle(color: _Colors.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final RunMode mode;
  final bool enabled;
  final ValueChanged<RunMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _InnerCard(
      title: '1 工作模式',
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'CV',
              subtitle: '恒压模式',
              selected: mode == RunMode.cv,
              onTap: enabled ? () => onChanged(RunMode.cv) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ModeButton(
              label: 'CC',
              subtitle: '恒流模式',
              selected: mode == RunMode.cc,
              onTap: enabled ? () => onChanged(RunMode.cc) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SetpointCard extends StatefulWidget {
  const _SetpointCard({
    required this.index,
    required this.title,
    required this.controller,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onSubmit,
  });

  final int index;
  final String title;
  final TextEditingController controller;
  final double min;
  final double max;
  final bool enabled;
  final Future<void> Function(double value) onSubmit;

  @override
  State<_SetpointCard> createState() => _SetpointCardState();
}

class _SetpointCardState extends State<_SetpointCard> {
  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(widget.controller.text) ?? widget.min;
    return _InnerCard(
      title: '${widget.index} ${widget.title}',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DarkField(
                  controller: widget.controller,
                  label: '',
                  enabled: widget.enabled,
                  textAlign: TextAlign.center,
                  fontSize: 24,
                ),
              ),
              IconButton(
                onPressed: widget.enabled
                    ? () => widget.onSubmit(
                        value.clamp(widget.min, widget.max).toDouble())
                    : null,
                tooltip: '写入参数',
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
            ],
          ),
          Slider(
            min: widget.min,
            max: widget.max,
            value: value.clamp(widget.min, widget.max),
            onChanged: widget.enabled
                ? (next) {
                    setState(
                        () => widget.controller.text = next.toStringAsFixed(2));
                  }
                : null,
            onChangeEnd:
                widget.enabled ? (next) => widget.onSubmit(next) : null,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.min.toStringAsFixed(2), style: _tinyText),
              Text(widget.max.toStringAsFixed(2), style: _tinyText),
            ],
          ),
        ],
      ),
    );
  }
}

class _FanCard extends StatelessWidget {
  const _FanCard({required this.fan, required this.onChanged});

  final bool fan;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _InnerCard(
      title: '4 风扇开关',
      child: Column(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: CustomPaint(
              painter: _FanIconPainter(active: fan),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('开启')),
              ButtonSegment(value: false, label: Text('关闭')),
            ],
            selected: {fan},
            onSelectionChanged: (value) => onChanged(value.first),
          ),
        ],
      ),
    );
  }
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    required this.direction,
    required this.enabled,
    required this.onChanged,
  });

  final PowerDirection direction;
  final bool enabled;
  final ValueChanged<PowerDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return _InnerCard(
      title: '5 功率方向',
      child: Column(
        children: [
          _DirectionButton(
            label: '左 → 右',
            selected: direction == PowerDirection.leftToRight,
            onTap: enabled ? () => onChanged(PowerDirection.leftToRight) : null,
          ),
          const SizedBox(height: 8),
          _DirectionButton(
            label: '右 ← 左',
            selected: direction == PowerDirection.rightToLeft,
            onTap: enabled ? () => onChanged(PowerDirection.rightToLeft) : null,
          ),
        ],
      ),
    );
  }
}

class _BottomStatusBar extends StatelessWidget {
  const _BottomStatusBar({required this.controller});

  final BidcdcController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: _Colors.panel,
        border: Border(top: BorderSide(color: _Colors.line)),
      ),
      child: Row(
        children: [
          _FooterItem(
            icon: Icons.timer_outlined,
            label: '运行时间',
            value: '00:00:00',
          ),
          _FooterItem(
            icon: Icons.memory,
            label: '系统状态',
            value: controller.connected ? '系统运行正常' : '设备离线',
            highlight: controller.connected,
          ),
          _FooterItem(
            icon: Icons.usb,
            label: '通信方式',
            value: 'USB 串口',
          ),
          _FooterItem(
            icon: Icons.monitor_heart_outlined,
            label: '通信状态',
            value: controller.message,
            highlight: controller.connected,
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.trailing,
    this.expandChild = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      color: _Colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _InnerCard extends StatelessWidget {
  const _InnerCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 198,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _Colors.inner,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _Colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(color: _Colors.text, fontSize: 12)),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    this.textAlign = TextAlign.start,
    this.fontSize = 13,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final TextAlign textAlign;
  final double fontSize;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textAlign: textAlign,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      style: TextStyle(color: _Colors.text, fontSize: fontSize),
      decoration: InputDecoration(
        labelText: label.isEmpty ? null : label,
        isDense: true,
        filled: true,
        fillColor: _Colors.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? _Colors.blue.withValues(alpha: 0.38)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: selected ? _Colors.blue : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 19, color: selected ? _Colors.text : _Colors.muted),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: selected ? _Colors.text : _Colors.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _DevicePlate extends StatelessWidget {
  const _DevicePlate();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _Colors.inner,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _Colors.line),
      ),
      child: Column(
        children: const [
          Icon(Icons.electrical_services, size: 58, color: _Colors.blue),
          SizedBox(height: 10),
          Text('双向四开关 Buck-Boost',
              textAlign: TextAlign.center,
              style: TextStyle(color: _Colors.text, fontSize: 12)),
          SizedBox(height: 8),
          Text('硬件版本：STM32F407\n固件版本：CV/CC BDC2',
              style: TextStyle(color: _Colors.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _TopMeta extends StatelessWidget {
  const _TopMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label：', style: const TextStyle(color: _Colors.muted)),
        Text(value, style: const TextStyle(color: _Colors.cyan)),
      ],
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle,
            size: 10, color: connected ? _Colors.green : _Colors.red),
        const SizedBox(width: 8),
        Text(
          connected ? '设备已连接' : '设备未连接',
          style: const TextStyle(color: _Colors.text, fontSize: 12),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: _Colors.text, fontSize: 13)),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

class _PdPresetTile extends StatelessWidget {
  const _PdPresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final _PdPreset preset;
  final bool selected;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _Colors.green : _Colors.blue;
    return InkWell(
      onTap: onTap == null ? null : () => unawaited(onTap!()),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 76,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color:
              selected ? _Colors.green.withValues(alpha: 0.16) : _Colors.inner,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? _Colors.green : _Colors.line),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _Colors.green.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.7)),
              ),
              child: Icon(Icons.electric_bolt, color: color, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${preset.voltage.toInt()}V',
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(preset.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: _Colors.muted, fontSize: 10)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: _Colors.green, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ProtectionRow extends StatelessWidget {
  const _ProtectionRow(this.label, this.ok);

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return _StatusLine(
      icon: Icons.shield_outlined,
      label: label,
      value: ok ? '正常' : '异常',
      color: ok ? _Colors.green : _Colors.red,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _Colors.muted)),
          ),
          const Spacer(),
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(color: _Colors.text)),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _Colors.blue : _Colors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? _Colors.cyan : _Colors.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : _Colors.muted,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle,
                style: TextStyle(
                    color: selected ? Colors.white : _Colors.muted,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? _Colors.green.withValues(alpha: 0.2)
              : _Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? _Colors.green : _Colors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _Colors.green : _Colors.muted,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  const _FooterItem({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: _Colors.muted, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _Colors.muted, fontSize: 11)),
                Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: highlight ? _Colors.green : _Colors.text,
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if ((maxValue - minValue).abs() < 0.001) {
      maxValue += 1;
      minValue -= 1;
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height -
          ((values[i] - minValue) / (maxValue - minValue)) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _FanIconPainter extends CustomPainter {
  _FanIconPainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final bladeColor = active ? _Colors.blue : _Colors.muted;
    final glowColor = active ? _Colors.cyan : _Colors.line;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: 0.26),
            _Colors.blue.withValues(alpha: active ? 0.14 : 0.04),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = glowColor.withValues(alpha: active ? 0.8 : 0.32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..cubicTo(
          center.dx + math.cos(angle + 0.18) * radius * 0.34,
          center.dy + math.sin(angle + 0.18) * radius * 0.34,
          center.dx + math.cos(angle + 0.54) * radius * 0.86,
          center.dy + math.sin(angle + 0.54) * radius * 0.86,
          center.dx + math.cos(angle + 0.9) * radius * 0.72,
          center.dy + math.sin(angle + 0.9) * radius * 0.72,
        )
        ..cubicTo(
          center.dx + math.cos(angle + 1.14) * radius * 0.38,
          center.dy + math.sin(angle + 1.14) * radius * 0.38,
          center.dx + math.cos(angle + 0.72) * radius * 0.18,
          center.dy + math.sin(angle + 0.72) * radius * 0.18,
          center.dx,
          center.dy,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [
              bladeColor.withValues(alpha: active ? 0.95 : 0.45),
              _Colors.cyan.withValues(alpha: active ? 0.42 : 0.14),
            ],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawCircle(
      center,
      radius * 0.2,
      Paint()
        ..color = bladeColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius * 0.2,
      Paint()
        ..color = _Colors.cyan.withValues(alpha: active ? 0.75 : 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _FanIconPainter oldDelegate) =>
      oldDelegate.active != active;
}

class _Colors {
  static const bg = Color(0xff020814);
  static const panel = Color(0xff071322);
  static const sidebar = Color(0xff05101e);
  static const inner = Color(0xff0a1a2b);
  static const line = Color(0xff1a3550);
  static const text = Color(0xffe6f2ff);
  static const muted = Color(0xff8fa6bd);
  static const cyan = Color(0xff00e5ff);
  static const blue = Color(0xff1687ff);
  static const green = Color(0xff45f06a);
  static const red = Color(0xffff4d4d);
}

const _tinyText = TextStyle(color: _Colors.muted, fontSize: 11);

BoxDecoration _boxDecoration() {
  return BoxDecoration(
    color: _Colors.panel,
    borderRadius: BorderRadius.circular(7),
    border: Border.all(color: _Colors.line),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.22),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

extension _TakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList(growable: false);
    return list.skip(math.max(0, list.length - count));
  }
}
