# BiDCDC CV/CC Serial Protocol 2.0

All multi-byte values use little-endian byte order. Requests are encoded as
`command + payload + CRC16(lo, hi)`. Responses are encoded as
`command + status + payload + CRC16(lo, hi)`.

The CRC is Modbus CRC16 with initial value `0xFFFF` and polynomial `0xA001`.

## Commands

| Code | Name | Request payload | Response payload |
| --- | --- | --- | --- |
| 1 | PWM test | `uint16 duty` | ACK |
| 2 | Ping | none | ACK |
| 3 | Read voltage ADC | none | `float UL, float UR` |
| 4 | Read current ADC | none | `float IL, float LIO, float RIO` |
| 5 | Fan | `uint8 enabled` | ACK |
| 6 | Set outer setpoint | `float value` | ACK |
| 7 | System command | `uint8 RUN/STOP` | ACK |
| 9 | Direction | `uint8 L2R/R2L` | ACK |
| 10 | Mode and setpoint | `uint8 CV/CC, float value` | ACK |
| 12 | Fault reset | none | ACK |
| 13 | Extended status | none | 68-byte status payload |
| 14 | Device info | none | 11-byte identity payload |
| 32 | Set PI | `uint8 loop, float Kp, float Ki` | ACK |
| 33 | Read PI | `uint8 loop` | `uint8 loop, float Kp, float Ki` |

Status codes are: `0 OK`, `1 bad length`, `2 bad parameter`, `3 bad CRC`,
`4 device error`, `5 busy`, and `6 unsupported`.

## Identity payload

`"BDC2" + protocol major + protocol minor + firmware major + firmware minor + firmware patch + uint16 capabilities`

## Extended status payload

The 68-byte payload contains:

1. `CMD, State, Direction, RunMode, Fault, Fan, uint16 PwmDuty`
2. `float OuterLoopSet, float InnerCurrentReference, float OcpLimit`
3. Calibrated values: `UL, UR, IL, LIO, RIO, Ta`
4. Raw ADC codes: `UL, UR, IL, LIO, RIO, Ta`

Direction and mode changes are accepted only while the device is idle. Command
10 applies the mode and its setpoint atomically.
