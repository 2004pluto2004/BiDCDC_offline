import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/protocol/commands.dart';
import '../core/protocol/frame.dart';
import '../core/protocol/models.dart';
import '../core/transport/device_transport.dart';
import '../core/transport/serial_transport.dart';
import 'device_config.dart';

class BidcdcController extends ChangeNotifier {
  BidcdcController({DeviceTransport? transport})
      : _transport = transport ?? SerialTransport() {
    _disconnectSubscription = _transport.disconnected.listen((_) {
      connected = false;
      message = 'Disconnected';
      _metricSampling = false;
      _pollTimer?.cancel();
      _pollTimer = null;
      _notify();
    });
  }

  final DeviceTransport _transport;
  StreamSubscription<void>? _disconnectSubscription;
  Timer? _pollTimer;
  bool _disposed = false;

  DeviceConfig config = const DeviceConfig();
  bool connected = false;
  String message = 'Disconnected';
  DeviceInfo? deviceInfo;
  DeviceStatus? status;
  final List<MetricSample> metricHistory = [];
  CalibrationCodes? calibrationCodes;
  bool _polling = false;
  int _statusFailureCount = 0;
  DateTime _pollPausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _startupGraceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _metricSampling = false;

  String get serialPort => config.serialPort;
  set serialPort(String value) =>
      updateConfig(config.copyWith(serialPort: value));

  int get baudRate => config.baudRate;
  set baudRate(int value) => updateConfig(config.copyWith(baudRate: value));

  void updateConfig(DeviceConfig value) {
    config = value;
    _notify();
    if (connected) _restartPolling();
  }

  Future<void> connect() async {
    try {
      await _transport.connect(config.serialPort, config.baudRate,
          timeout: config.connectTimeout);
      final infoResponse = await _send(
        DeviceCommands.noPayload(DeviceCommands.deviceInfo),
        expectedResponseLength: 15,
      );
      if (!infoResponse.isOk) {
        throw ProtocolException('Device identification failed.');
      }
      final info = DeviceInfo.fromPayload(infoResponse.payload);
      if (info.protocolMajor != 2) {
        throw ProtocolException(
            'Unsupported protocol ${info.protocolVersion}.');
      }
      deviceInfo = info;
      connected = true;
      _startupGraceUntil = DateTime.now().add(const Duration(seconds: 3));
      _statusFailureCount = 0;
      _metricSampling = false;
      metricHistory.clear();
      message = 'Connected to ${config.serialPort} @ ${config.baudRate}';
      _notify();
      await _readInitialStatus();
      _metricSampling = _isDeviceRunning;
      _restartPolling();
    } catch (error) {
      connected = false;
      message = '$error';
      await _transport.close();
      _notify();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _transport.close();
    connected = false;
    _metricSampling = false;
    message = 'Disconnected';
    _notify();
  }

  Future<void> refreshAll() async {
    await readStatus();
  }

  Future<void> run(
    PowerDirection direction,
    RunMode mode,
    double setpoint,
  ) =>
      _commandWithPollPause(
        () async {
          metricHistory.clear();
          _notify();
          await _requireAck(DeviceCommands.oneByte(
              DeviceCommands.setDirection, direction.id));
          await _requireAck(DeviceCommands.modeSetpoint(mode, setpoint));
          await readStatus();
          final configured = status;
          if (configured == null ||
              configured.direction != direction.id ||
              configured.runMode != mode.id ||
              (configured.outerLoopSet - setpoint).abs() > 0.01) {
            throw ProtocolException(
                'Device configuration verification failed.');
          }
          await _requireAck(DeviceCommands.oneByte(
              DeviceCommands.setSystemCommand, SystemCommand.run.id));
          await readStatus();
          _metricSampling = _isDeviceRunning;
          _notify();
        },
      );

  Future<void> stop() => _commandWithPollPause(
        () async {
          _metricSampling = false;
          _notify();
          await _requireAck(DeviceCommands.oneByte(
              DeviceCommands.setSystemCommand, SystemCommand.stop.id));
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await readStatus();
        },
      );

  Future<void> resetFault() => _commandWithPollPause(
        () async {
          await _requireAck(
              DeviceCommands.noPayload(DeviceCommands.faultReset));
          await readStatus();
        },
      );

  Future<void> setFan(bool enabled) => _commandWithPollPause(
        () async {
          await _requireAck(
              DeviceCommands.oneByte(DeviceCommands.fan, enabled ? 1 : 0));
          await readStatus();
        },
      );

  Future<void> setPwmDuty(int duty) =>
      _requireAck(DeviceCommands.pwm(duty.clamp(0, 2100).toInt()));

  Future<void> setOuterLoopSet(double value) async {
    await _commandWithPollPause(() async {
      await _requireAck(
          DeviceCommands.floatValue(DeviceCommands.setOuterSetpoint, value));
      await readStatus();
    });
  }

  Future<void> setModeAndSetpoint(RunMode mode, double value) async {
    await _commandWithPollPause(() async {
      await _requireAck(DeviceCommands.modeSetpoint(mode, value));
      await readStatus();
    });
  }

  Future<void> setDirection(PowerDirection direction) {
    return _commandWithPollPause(
      () async {
        await _requireAck(
            DeviceCommands.oneByte(DeviceCommands.setDirection, direction.id));
        await readStatus();
      },
    );
  }

  Future<void> readCalibrationCodes() async {
    final voltageResponse = await _send(
      DeviceCommands.noPayload(DeviceCommands.readVoltageCode),
      expectedResponseLength: 12,
    );
    final currentResponse = await _send(
      DeviceCommands.noPayload(DeviceCommands.readCurrentCode),
      expectedResponseLength: 16,
    );
    if (voltageResponse.isOk && currentResponse.isOk) {
      calibrationCodes = CalibrationCodes(
        ulCode: readFloat32le(voltageResponse.payload, 0),
        urCode: readFloat32le(voltageResponse.payload, 4),
        ilCode: readFloat32le(currentResponse.payload, 0),
        lioCode: readFloat32le(currentResponse.payload, 4),
        rioCode: readFloat32le(currentResponse.payload, 8),
      );
      message = 'Calibration codes updated';
      _notify();
    }
  }

  Future<void> readStatus() async {
    final response = await _send(
      DeviceCommands.noPayload(DeviceCommands.readStatusEx),
      expectedResponseLength: 72,
    );
    if (response.isOk) {
      status = DeviceStatus.fromExtendedPayload(response.payload);
      if (_metricSampling && _isDeviceRunning) {
        _recordMetricSample(status!);
      }
      _statusFailureCount = 0;
      _notify();
    }
  }

  Future<DeviceResponse> _ack(DeviceFrame frame) async {
    final response = await _send(frame, expectedResponseLength: 4);
    message = response.isOk ? 'OK' : 'Device status ${response.status}';
    _notify();
    return response;
  }

  Future<void> _requireAck(DeviceFrame frame) async {
    final response = await _ack(frame);
    if (!response.isOk) {
      throw ProtocolException(
          'Command ${frame.command} rejected with status ${response.status}.');
    }
  }

  Future<DeviceResponse> _send(
    DeviceFrame frame, {
    required int expectedResponseLength,
    Duration? timeout,
  }) async {
    final response = await _transport.send(
      frame,
      expectedResponseLength: expectedResponseLength,
      timeout: timeout ?? config.commandTimeout,
    );
    if (!response.isOk) {
      message = 'Device status ${response.status}';
      _notify();
    }
    return response;
  }

  void _restartPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(config.pollInterval, (_) => _pollTick());
  }

  Future<void> _pollTick() async {
    if (_polling) return;
    if (DateTime.now().isBefore(_pollPausedUntil)) return;
    _polling = true;
    try {
      await readStatus();
    } catch (error) {
      _statusFailureCount++;
      final inStartupGrace = DateTime.now().isBefore(_startupGraceUntil);
      if (!inStartupGrace && _statusFailureCount >= 5) {
        await _markOffline('Offline: $error');
      } else {
        message = 'Retrying: $error';
        _notify();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _readInitialStatus() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        await readStatus();
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    if (lastError != null) throw lastError;
    throw TimeoutException('Initial status timed out.');
  }

  Future<void> _commandWithPollPause(Future<void> Function() action) async {
    _pollPausedUntil = DateTime.now().add(const Duration(seconds: 2));
    try {
      await action();
      _statusFailureCount = 0;
    } finally {
      _pollPausedUntil = DateTime.now().add(const Duration(seconds: 2));
    }
  }

  Future<void> _markOffline(String reason) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    connected = false;
    _metricSampling = false;
    message = reason;
    await _transport.close();
    _notify();
  }

  bool get _isDeviceRunning {
    final current = status;
    if (current == null) return false;
    return current.command == SystemCommand.run.id ||
        current.state == SystemCommand.run.id;
  }

  void _recordMetricSample(DeviceStatus value) {
    metricHistory.add(MetricSample.fromStatus(value));
    if (metricHistory.length > 240) {
      metricHistory.removeRange(0, metricHistory.length - 240);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_disconnectSubscription?.cancel());
    unawaited(_transport.close());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

class MetricSample {
  const MetricSample({
    required this.inputVoltage,
    required this.outputVoltage,
    required this.outputCurrent,
    required this.outputPower,
  });

  final double inputVoltage;
  final double outputVoltage;
  final double outputCurrent;
  final double outputPower;

  static MetricSample fromStatus(DeviceStatus status) {
    final isLeftToRight = status.direction == PowerDirection.leftToRight.id;
    final inputVoltage =
        isLeftToRight ? status.leftVoltage : status.rightVoltage;
    final outputVoltage =
        isLeftToRight ? status.rightVoltage : status.leftVoltage;
    final outputCurrent = (isLeftToRight
            ? status.rightInputOutputCurrent
            : status.leftInputOutputCurrent)
        .abs();
    return MetricSample(
      inputVoltage: inputVoltage,
      outputVoltage: outputVoltage,
      outputCurrent: outputCurrent,
      outputPower: outputVoltage * outputCurrent,
    );
  }
}

class CalibrationCodes {
  const CalibrationCodes({
    required this.ulCode,
    required this.urCode,
    required this.ilCode,
    required this.lioCode,
    required this.rioCode,
  });

  final double ulCode;
  final double urCode;
  final double ilCode;
  final double lioCode;
  final double rioCode;
}
