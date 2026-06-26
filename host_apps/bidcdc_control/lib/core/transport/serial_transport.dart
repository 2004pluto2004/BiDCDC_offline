import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../protocol/frame.dart';
import 'device_transport.dart';

class SerialTransport implements DeviceTransport {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;
  final _disconnects = StreamController<void>.broadcast();
  final _rx = Queue<int>();
  Completer<DeviceResponse>? _pending;
  int _pendingLength = 0;
  int _pendingCommand = 0;
  Future<void> _tail = Future.value();

  static List<String> get availablePorts => SerialPort.availablePorts;

  @override
  bool get isConnected => _port != null && (_port?.isOpen ?? false);

  @override
  Stream<void> get disconnected => _disconnects.stream;

  @override
  Future<void> connect(String portName, int baudRate,
      {Duration timeout = const Duration(seconds: 3)}) async {
    await close();
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw StateError('Open serial port $portName failed: $error');
    }

    port.config = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none
      ..setFlowControl(SerialPortFlowControl.none);

    _port = port;
    _reader = SerialPortReader(port);
    _subscription = _reader!.stream.listen(_onData,
        onDone: _handleDisconnected, onError: (_) => _handleDisconnected());
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _reader = null;
    final port = _port;
    _port = null;
    if (port != null) {
      if (port.isOpen) port.close();
      port.dispose();
    }
    _rx.clear();
    _pending?.completeError(ProtocolException('Connection closed.'));
    _pending = null;
  }

  @override
  Future<DeviceResponse> send(
    DeviceFrame frame, {
    required int expectedResponseLength,
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    final operation = _tail.then((_) {
      return _sendNow(
        frame,
        expectedResponseLength: expectedResponseLength,
        timeout: timeout,
      );
    });
    _tail = operation.then((_) {}, onError: (_) {});
    return operation;
  }

  Future<DeviceResponse> _sendNow(
    DeviceFrame frame, {
    required int expectedResponseLength,
    required Duration timeout,
  }) async {
    final port = _port;
    if (port == null || !port.isOpen) {
      throw StateError('Serial transport is not connected.');
    }
    if (_pending != null) {
      throw StateError('A command is already waiting for a response.');
    }

    _pending = Completer<DeviceResponse>();
    final completer = _pending!;
    _pendingLength = expectedResponseLength;
    _pendingCommand = frame.command;
    _rx.clear();
    final bytes = frame.encode();
    final written = port.write(bytes);
    if (written != bytes.length) {
      _pending = null;
      _pendingLength = 0;
      _pendingCommand = 0;
      throw StateError(
          'Serial write incomplete: $written/${bytes.length} bytes.');
    }
    _drainPending();
    return completer.future.timeout(timeout, onTimeout: () {
      if (identical(_pending, completer)) {
        _pending = null;
        _pendingLength = 0;
        _pendingCommand = 0;
      }
      throw TimeoutException('Command ${frame.command} timed out.');
    });
  }

  Future<void> _handleDisconnected() async {
    final wasConnected = isConnected;
    await close();
    if (wasConnected) _disconnects.add(null);
  }

  void _onData(Uint8List data) {
    _rx.addAll(data);
    _drainPending();
  }

  void _drainPending() {
    final pending = _pending;
    if (pending == null) return;
    while (_rx.length >= _pendingLength) {
      final bytes = _rx.take(_pendingLength).toList();
      try {
        final response = DeviceResponse.decode(Uint8List.fromList(bytes));
        if (response.command != _pendingCommand) {
          throw ProtocolException(
              'Unexpected response command ${response.command}.');
        }
        for (var i = 0; i < _pendingLength; i++) {
          _rx.removeFirst();
        }
        _pending = null;
        pending.complete(response);
        return;
      } catch (_) {
        _rx.removeFirst();
      }
    }
  }
}
