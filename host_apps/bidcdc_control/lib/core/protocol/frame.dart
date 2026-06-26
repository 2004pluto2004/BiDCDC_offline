import 'dart:typed_data';

import 'crc16.dart';

class ProtocolException implements Exception {
  ProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}

class DeviceFrame {
  DeviceFrame(this.command, [List<int> payload = const []])
      : payload = Uint8List.fromList(payload);

  final int command;
  final Uint8List payload;

  Uint8List encode() {
    final body = Uint8List(1 + payload.length);
    body[0] = command;
    body.setAll(1, payload);
    final crc = modbusCrc16(body);
    return Uint8List.fromList([
      ...body,
      crc & 0xff,
      (crc >> 8) & 0xff,
    ]);
  }
}

class DeviceResponse {
  DeviceResponse({
    required this.command,
    required this.status,
    required this.payload,
  });

  final int command;
  final int status;
  final Uint8List payload;

  bool get isOk => status == 0;

  static DeviceResponse decode(List<int> frame) {
    if (frame.length < 4) {
      throw ProtocolException('Frame too short.');
    }
    final expected = modbusCrc16(frame.sublist(0, frame.length - 2));
    final actual = frame[frame.length - 2] | (frame[frame.length - 1] << 8);
    if (expected != actual) {
      throw ProtocolException('CRC mismatch.');
    }
    return DeviceResponse(
      command: frame[0],
      status: frame[1],
      payload: Uint8List.fromList(frame.sublist(2, frame.length - 2)),
    );
  }
}

Uint8List float32le(double value) {
  final bytes = ByteData(4)..setFloat32(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}

Uint8List uint16le(int value) {
  final bytes = ByteData(2)..setUint16(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}

double readFloat32le(Uint8List payload, int offset) {
  return ByteData.sublistView(payload).getFloat32(offset, Endian.little);
}

int readUint16le(Uint8List payload, int offset) {
  return ByteData.sublistView(payload).getUint16(offset, Endian.little);
}
