import 'dart:typed_data';

import 'package:bidcdc_control/core/protocol/commands.dart';
import 'package:bidcdc_control/core/protocol/crc16.dart';
import 'package:bidcdc_control/core/protocol/frame.dart';
import 'package:bidcdc_control/core/protocol/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modbus crc16 matches known value', () {
    expect(modbusCrc16([0x02]), 0x813e);
  });

  test('outer setpoint frame uses float32 little endian plus crc', () {
    final frame = DeviceCommands.floatValue(
      DeviceCommands.setOuterSetpoint,
      15,
    ).encode();
    expect(frame[0], 6);
    expect(frame.sublist(1, 5), float32le(15));
    expect(modbusCrc16(frame.sublist(0, frame.length - 2)),
        frame[frame.length - 2] | (frame.last << 8));
  });

  test('mode and setpoint are encoded atomically', () {
    final frame = DeviceCommands.modeSetpoint(RunMode.cc, 1.25).encode();
    expect(frame[0], DeviceCommands.setModeSetpoint);
    expect(frame[1], RunMode.cc.id);
    expect(readFloat32le(Uint8List.fromList(frame), 2), closeTo(1.25, 0.0001));
  });

  test('device info validates BDC2 protocol identity', () {
    final info = DeviceInfo.fromPayload(Uint8List.fromList([
      ...'BDC2'.codeUnits,
      2,
      0,
      1,
      0,
      0,
      ...uint16le(0x1b),
    ]));
    expect(info.protocolVersion, '2.0');
    expect(info.firmwareVersion, '1.0.0');
    expect(info.capabilities, 0x1b);
  });

  test('status payload parses CV CC fields measurements and ADC codes', () {
    final status = DeviceStatus.fromExtendedPayload(_statusPayload(
      command: 1,
      state: 1,
      direction: 1,
      mode: 1,
      outerSetpoint: 1.25,
    ));
    expect(status.outerLoopSet, closeTo(1.25, 0.0001));
    expect(status.innerCurrentReference, 0.75);
    expect(status.temperature, 42);
    expect(status.leftVoltage, 15);
    expect(status.rightInputOutputCurrent, closeTo(-1.1, 0.0001));
    expect(status.adcCodes, [1100, 1200, 1300, 1400, 1500, 1600]);
  });

  test('ack and error responses parse status codes', () {
    final ok =
        DeviceResponse.decode(DeviceFrame(DeviceCommands.ping, [0]).encode());
    final busy =
        DeviceResponse.decode(DeviceFrame(DeviceCommands.fan, [5]).encode());
    expect(ok.status, 0);
    expect(busy.status, 5);
  });
}

Uint8List _statusPayload({
  required int command,
  required int state,
  required int direction,
  required int mode,
  required double outerSetpoint,
}) {
  return Uint8List.fromList([
    command,
    state,
    direction,
    mode,
    0,
    1,
    ...uint16le(1050),
    ...float32le(outerSetpoint),
    ...float32le(0.75),
    ...float32le(15),
    ...float32le(15),
    ...float32le(20),
    ...float32le(0.8),
    ...float32le(1.2),
    ...float32le(-1.1),
    ...float32le(42),
    ...float32le(1100),
    ...float32le(1200),
    ...float32le(1300),
    ...float32le(1400),
    ...float32le(1500),
    ...float32le(1600),
  ]);
}
