class DeviceConfig {
  const DeviceConfig({
    this.serialPort = 'COM3',
    this.baudRate = 115200,
    this.connectTimeout = const Duration(seconds: 3),
    this.commandTimeout = const Duration(seconds: 2),
    this.pollInterval = const Duration(seconds: 1),
  });

  final String serialPort;
  final int baudRate;
  final Duration connectTimeout;
  final Duration commandTimeout;
  final Duration pollInterval;

  DeviceConfig copyWith({
    String? serialPort,
    int? baudRate,
    Duration? connectTimeout,
    Duration? commandTimeout,
    Duration? pollInterval,
  }) {
    return DeviceConfig(
      serialPort: serialPort ?? this.serialPort,
      baudRate: baudRate ?? this.baudRate,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      commandTimeout: commandTimeout ?? this.commandTimeout,
      pollInterval: pollInterval ?? this.pollInterval,
    );
  }
}
