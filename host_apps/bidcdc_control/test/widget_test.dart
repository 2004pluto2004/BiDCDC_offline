import 'dart:async';
import 'dart:typed_data';

import 'package:bidcdc_control/core/protocol/commands.dart';
import 'package:bidcdc_control/core/protocol/frame.dart';
import 'package:bidcdc_control/core/protocol/models.dart';
import 'package:bidcdc_control/core/transport/device_transport.dart';
import 'package:bidcdc_control/domain/bidcdc_controller.dart';
import 'package:bidcdc_control/features/dashboard/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bidcdc_control/main.dart';

void main() {
  testWidgets('BiDCDC dashboard renders connection controls', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BidcdcApp());

    expect(find.text('双向升降压电源上位机'), findsOneWidget);
    expect(find.text('v0.3.1'), findsWidgets);
    expect(find.text('核心控制'), findsOneWidget);
    expect(find.text('PD 多档电压预设'), findsOneWidget);
  });

  testWidgets('CC mode changes setpoint semantics and disables PD presets',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = UiTransport();
    final controller = BidcdcController(transport: transport)
      ..connected = true
      ..status = _status(RunMode.cv, 2);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: DashboardPage(controller: controller),
    ));
    expect(find.textContaining('输出电压设定 (V)'), findsOneWidget);

    await tester.tap(find.text('CC').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('输出电流设定 (A)'), findsOneWidget);
    final pdInkWell = tester.widget<InkWell>(
      find.ancestor(of: find.text('5V'), matching: find.byType(InkWell)).first,
    );
    expect(pdInkWell.onTap, isNull);
  });
}

class UiTransport implements DeviceTransport {
  final _disconnects = StreamController<void>.broadcast();
  RunMode mode = RunMode.cv;
  double setpoint = 2;

  @override
  bool get isConnected => true;

  @override
  Stream<void> get disconnected => _disconnects.stream;

  @override
  Future<void> close() async {}

  @override
  Future<void> connect(String portName, int baudRate,
      {Duration timeout = const Duration(seconds: 3)}) async {}

  @override
  Future<DeviceResponse> send(
    DeviceFrame frame, {
    required int expectedResponseLength,
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    if (frame.command == DeviceCommands.setModeSetpoint) {
      mode = frame.payload[0] == RunMode.cc.id ? RunMode.cc : RunMode.cv;
      setpoint = readFloat32le(frame.payload, 1);
      return DeviceResponse(
        command: frame.command,
        status: 0,
        payload: Uint8List(0),
      );
    }
    if (frame.command == DeviceCommands.readStatusEx) {
      return DeviceResponse(
        command: frame.command,
        status: 0,
        payload: _statusPayload(mode, setpoint),
      );
    }
    throw StateError('Unexpected command ${frame.command}');
  }
}

DeviceStatus _status(RunMode mode, double setpoint) => DeviceStatus(
      command: 0,
      state: 0,
      direction: 0,
      runMode: mode.id,
      outerLoopSet: setpoint,
      innerCurrentReference: 0,
      ocpLimit: 15,
      leftVoltage: 20,
      rightVoltage: 15,
      inductorCurrent: 0,
    );

Uint8List _statusPayload(RunMode mode, double setpoint) => Uint8List.fromList([
      0,
      0,
      0,
      mode.id,
      0,
      0,
      ...uint16le(1050),
      ...float32le(setpoint),
      ...float32le(0),
      ...float32le(15),
      ...float32le(20),
      ...float32le(15),
      ...float32le(0),
      ...float32le(0),
      ...float32le(0),
      ...float32le(42),
      ...float32le(1000),
      ...float32le(1100),
      ...float32le(1200),
      ...float32le(1300),
      ...float32le(1400),
      ...float32le(1500),
    ]);
