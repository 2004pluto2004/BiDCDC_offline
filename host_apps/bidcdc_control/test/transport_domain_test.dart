import 'dart:async';
import 'dart:typed_data';

import 'package:bidcdc_control/core/protocol/commands.dart';
import 'package:bidcdc_control/core/protocol/frame.dart';
import 'package:bidcdc_control/core/protocol/models.dart';
import 'package:bidcdc_control/core/transport/device_transport.dart';
import 'package:bidcdc_control/domain/bidcdc_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller rejects firmware without BDC2 identity', () async {
    final transport = ScriptedTransport([
      _response(
          DeviceCommands.deviceInfo,
          Uint8List.fromList([
            ...'OLD1'.codeUnits,
            1,
            0,
            1,
            0,
            0,
            0,
            0,
          ])),
    ]);
    final controller = BidcdcController(transport: transport);
    addTearDown(controller.dispose);

    await expectLater(controller.connect(), throwsA(isA<ProtocolException>()));
    expect(controller.connected, isFalse);
  });

  test('run configures direction and mode before enabling output', () async {
    final transport = ScriptedTransport([
      _ack(DeviceCommands.setDirection),
      _ack(DeviceCommands.setModeSetpoint),
      _response(
        DeviceCommands.readStatusEx,
        _statusPayload(direction: 1, mode: 1, setpoint: 1.25),
      ),
      _ack(DeviceCommands.setSystemCommand),
      _response(
        DeviceCommands.readStatusEx,
        _statusPayload(
          command: 1,
          state: 1,
          direction: 1,
          mode: 1,
          setpoint: 1.25,
        ),
      ),
    ]);
    final controller = BidcdcController(transport: transport);
    addTearDown(controller.dispose);

    await controller.run(PowerDirection.rightToLeft, RunMode.cc, 1.25);

    expect(transport.sent.map((frame) => frame.command), [9, 10, 13, 7, 13]);
    expect(transport.sent[1].payload[0], RunMode.cc.id);
    expect(readFloat32le(transport.sent[1].payload, 1), closeTo(1.25, 0.0001));
    expect(controller.status?.state, SystemCommand.run.id);
  });

  test('stop reads firmware defaults back into status', () async {
    final transport = ScriptedTransport([
      _ack(DeviceCommands.setSystemCommand),
      _response(
        DeviceCommands.readStatusEx,
        _statusPayload(direction: 0, mode: 0, setpoint: 2),
      ),
    ]);
    final controller = BidcdcController(transport: transport);
    addTearDown(controller.dispose);

    await controller.stop();

    expect(controller.status?.command, SystemCommand.idle.id);
    expect(controller.status?.direction, PowerDirection.leftToRight.id);
    expect(controller.status?.runMode, RunMode.cv.id);
    expect(controller.status?.outerLoopSet, 2);
  });

  test('controller surfaces device error responses', () async {
    final transport = ScriptedTransport([
      DeviceResponse(
        command: DeviceCommands.fan,
        status: 2,
        payload: Uint8List(0),
      ),
    ]);
    final controller = BidcdcController(transport: transport);
    addTearDown(controller.dispose);

    await expectLater(
        controller.setFan(true), throwsA(isA<ProtocolException>()));
    expect(controller.message, 'Device status 2');
  });

  test('metric sample maps output side by power direction', () {
    final leftToRight = MetricSample.fromStatus(
      _status(direction: 0, leftIo: 2, rightIo: -1),
    );
    expect(leftToRight.inputVoltage, 20);
    expect(leftToRight.outputVoltage, 15);
    expect(leftToRight.outputCurrent, 1);
    expect(leftToRight.outputPower, 15);

    final rightToLeft = MetricSample.fromStatus(
      _status(direction: 1, leftIo: -1.2, rightIo: 2),
    );
    expect(rightToLeft.inputVoltage, 15);
    expect(rightToLeft.outputVoltage, 20);
    expect(rightToLeft.outputCurrent, closeTo(1.2, 0.0001));
    expect(rightToLeft.outputPower, closeTo(24, 0.0001));
  });
}

class ScriptedTransport implements DeviceTransport {
  ScriptedTransport(this.responses);

  final List<Object> responses;
  final List<DeviceFrame> sent = [];
  final _disconnects = StreamController<void>.broadcast();
  bool _connected = true;

  @override
  bool get isConnected => _connected;

  @override
  Stream<void> get disconnected => _disconnects.stream;

  @override
  Future<void> close() async {
    _connected = false;
  }

  @override
  Future<void> connect(String portName, int baudRate,
      {Duration timeout = const Duration(seconds: 3)}) async {
    _connected = true;
  }

  @override
  Future<DeviceResponse> send(
    DeviceFrame frame, {
    required int expectedResponseLength,
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    sent.add(frame);
    final response = responses.removeAt(0);
    if (response is Exception) throw response;
    return response as DeviceResponse;
  }
}

DeviceResponse _ack(int command) =>
    DeviceResponse(command: command, status: 0, payload: Uint8List(0));

DeviceResponse _response(int command, Uint8List payload) =>
    DeviceResponse(command: command, status: 0, payload: payload);

DeviceStatus _status({
  required int direction,
  required double leftIo,
  required double rightIo,
}) {
  return DeviceStatus(
    command: 1,
    state: 1,
    direction: direction,
    runMode: 0,
    outerLoopSet: 15,
    innerCurrentReference: 1,
    ocpLimit: 15,
    leftVoltage: 20,
    rightVoltage: 15,
    inductorCurrent: 1,
    leftInputOutputCurrent: leftIo,
    rightInputOutputCurrent: rightIo,
  );
}

Uint8List _statusPayload({
  int command = 0,
  int state = 0,
  required int direction,
  required int mode,
  required double setpoint,
}) {
  return Uint8List.fromList([
    command,
    state,
    direction,
    mode,
    0,
    0,
    ...uint16le(1050),
    ...float32le(setpoint),
    ...float32le(0.5),
    ...float32le(15),
    ...float32le(20),
    ...float32le(15),
    ...float32le(1),
    ...float32le(0.8),
    ...float32le(-1),
    ...float32le(42),
    ...float32le(1000),
    ...float32le(1100),
    ...float32le(1200),
    ...float32le(1300),
    ...float32le(1400),
    ...float32le(1500),
  ]);
}
