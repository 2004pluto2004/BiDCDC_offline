# BiDCDC Control Host App

This Flutter source tree targets:

- Windows PC host: waveform display, parameter setup, PID tuning.

The host app connects directly to the STM32 UART through a USB-to-serial adapter:

`Host app serial port -> USART1 115200 8N1 -> STM32F407`

## First setup

Flutter is not installed on this machine at the time this source was created. After installing Flutter, run:

```powershell
cd host_apps\bidcdc_control
flutter create . --platforms=windows,android
flutter test
flutter run -d windows
```

## Protocol summary

Frame format is compatible with the firmware APP/COMM module:

`cmd(1 byte) + payload(n bytes) + modbus_crc16_low + modbus_crc16_high`

Binary responses use:

`cmd(1 byte) + status(1 byte) + payload(n bytes) + crc_low + crc_high`

The waveform command returns six float32 little-endian channels:

| Channel | Variable | Meaning |
| --- | --- | --- |
| CH1 | VoltagePI.Reference | Voltage loop reference |
| CH2 | VoltagePI.FeedBack | Voltage loop feedback |
| CH3 | VoltagePI.Error | Voltage loop error |
| CH4 | CurrentPI.Reference | Current loop reference |
| CH5 | CurrentPI.FeedBack | Current loop feedback |
| CH6 | CurrentPI.Error | Current loop error |

PID tuning is online. `setPid(loop, kp, ki)` writes Kp/Ki to the active firmware PI structs, so the next control interrupt uses the new values.
