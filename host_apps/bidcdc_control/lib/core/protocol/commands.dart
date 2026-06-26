import 'frame.dart';
import 'models.dart';

class DeviceCommands {
  static const pwmTest = 1;
  static const ping = 2;
  static const readVoltageCode = 3;
  static const readCurrentCode = 4;
  static const fan = 5;
  static const setOuterSetpoint = 6;
  static const setSystemCommand = 7;
  static const setDirection = 9;
  static const setModeSetpoint = 10;
  static const faultReset = 12;
  static const readStatusEx = 13;
  static const deviceInfo = 14;

  static DeviceFrame noPayload(int command) => DeviceFrame(command);

  static DeviceFrame oneByte(int command, int value) {
    return DeviceFrame(command, [value & 0xff]);
  }

  static DeviceFrame floatValue(int command, double value) {
    return DeviceFrame(command, float32le(value));
  }

  static DeviceFrame modeSetpoint(RunMode mode, double value) {
    return DeviceFrame(setModeSetpoint, [mode.id, ...float32le(value)]);
  }

  static DeviceFrame pwm(int duty) {
    return DeviceFrame(pwmTest, uint16le(duty));
  }
}
