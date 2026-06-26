import 'dart:typed_data';

import 'frame.dart';

enum SystemCommand {
  idle(0, 'Idle'),
  run(1, 'Run'),
  stop(2, 'Stop'),
  fault(3, 'Fault'),
  reset(12, 'Reset');

  const SystemCommand(this.id, this.label);

  final int id;
  final String label;
}

enum PowerDirection {
  leftToRight(0, 'L2R'),
  rightToLeft(1, 'R2L');

  const PowerDirection(this.id, this.label);

  final int id;
  final String label;
}

enum RunMode {
  cv(0, 'CV'),
  cc(1, 'CC');

  const RunMode(this.id, this.label);

  final int id;
  final String label;
}

class DeviceInfo {
  const DeviceInfo({
    required this.protocolMajor,
    required this.protocolMinor,
    required this.firmwareMajor,
    required this.firmwareMinor,
    required this.firmwarePatch,
    required this.capabilities,
  });

  final int protocolMajor;
  final int protocolMinor;
  final int firmwareMajor;
  final int firmwareMinor;
  final int firmwarePatch;
  final int capabilities;

  String get protocolVersion => '$protocolMajor.$protocolMinor';
  String get firmwareVersion => '$firmwareMajor.$firmwareMinor.$firmwarePatch';

  static DeviceInfo fromPayload(Uint8List payload) {
    if (payload.length < 11 ||
        String.fromCharCodes(payload.sublist(0, 4)) != 'BDC2') {
      throw ProtocolException('Unsupported firmware protocol.');
    }
    return DeviceInfo(
      protocolMajor: payload[4],
      protocolMinor: payload[5],
      firmwareMajor: payload[6],
      firmwareMinor: payload[7],
      firmwarePatch: payload[8],
      capabilities: readUint16le(payload, 9),
    );
  }
}

class WaveformSample {
  const WaveformSample({
    required this.voltageReference,
    required this.voltageFeedback,
    required this.voltageError,
    required this.currentReference,
    required this.currentFeedback,
    required this.currentError,
  });

  final double voltageReference;
  final double voltageFeedback;
  final double voltageError;
  final double currentReference;
  final double currentFeedback;
  final double currentError;

  List<double> get channels => [
        voltageReference,
        voltageFeedback,
        voltageError,
        currentReference,
        currentFeedback,
        currentError,
      ];

  static WaveformSample fromPayload(Uint8List payload) {
    if (payload.length < 24) {
      throw ProtocolException('Waveform payload too short.');
    }
    return WaveformSample(
      voltageReference: readFloat32le(payload, 0),
      voltageFeedback: readFloat32le(payload, 4),
      voltageError: readFloat32le(payload, 8),
      currentReference: readFloat32le(payload, 12),
      currentFeedback: readFloat32le(payload, 16),
      currentError: readFloat32le(payload, 20),
    );
  }

  static WaveformSample fromStatus(DeviceStatus status) {
    return WaveformSample(
      voltageReference: status.outerLoopSet,
      voltageFeedback: status.rightVoltage,
      voltageError: status.outerLoopSet - status.rightVoltage,
      currentReference: status.innerCurrentReference,
      currentFeedback: status.inductorCurrent,
      currentError: status.innerCurrentReference - status.inductorCurrent,
    );
  }
}

class DeviceStatus {
  const DeviceStatus({
    required this.command,
    required this.state,
    required this.direction,
    required this.runMode,
    required this.outerLoopSet,
    required this.innerCurrentReference,
    required this.ocpLimit,
    required this.leftVoltage,
    required this.rightVoltage,
    required this.inductorCurrent,
    this.faultCode = 0,
    this.fanEnabled = false,
    this.pwmDuty = 0,
    this.leftInputOutputCurrent = 0,
    this.rightInputOutputCurrent = 0,
    this.temperature = 0,
    this.adcCodes = const [],
  });

  final int command;
  final int state;
  final int direction;
  final int runMode;
  final double outerLoopSet;
  final double innerCurrentReference;
  final double ocpLimit;
  final double leftVoltage;
  final double rightVoltage;
  final double inductorCurrent;
  final int faultCode;
  final bool fanEnabled;
  final int pwmDuty;
  final double leftInputOutputCurrent;
  final double rightInputOutputCurrent;
  final double temperature;
  final List<double> adcCodes;

  static DeviceStatus fromExtendedPayload(Uint8List payload) {
    if (payload.length < 68) {
      throw ProtocolException('Extended status payload too short.');
    }
    return DeviceStatus(
      command: payload[0],
      state: payload[1],
      direction: payload[2],
      runMode: payload[3],
      faultCode: payload[4],
      fanEnabled: payload[5] != 0,
      pwmDuty: readUint16le(payload, 6),
      outerLoopSet: readFloat32le(payload, 8),
      innerCurrentReference: readFloat32le(payload, 12),
      ocpLimit: readFloat32le(payload, 16),
      leftVoltage: readFloat32le(payload, 20),
      rightVoltage: readFloat32le(payload, 24),
      inductorCurrent: readFloat32le(payload, 28),
      leftInputOutputCurrent: readFloat32le(payload, 32),
      rightInputOutputCurrent: readFloat32le(payload, 36),
      temperature: readFloat32le(payload, 40),
      adcCodes: [
        for (var offset = 44; offset < 68; offset += 4)
          readFloat32le(payload, offset),
      ],
    );
  }
}
