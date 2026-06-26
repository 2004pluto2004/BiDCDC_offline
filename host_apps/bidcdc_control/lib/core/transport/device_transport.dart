import '../protocol/frame.dart';

abstract class DeviceTransport {
  bool get isConnected;
  Stream<void> get disconnected;

  Future<void> connect(String portName, int baudRate, {Duration timeout});
  Future<void> close();
  Future<DeviceResponse> send(
    DeviceFrame frame, {
    required int expectedResponseLength,
    Duration timeout,
  });
}
