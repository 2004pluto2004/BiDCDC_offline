#include "COMM.h"

#include <string.h>

#include "Control.h"
#include "Feedback.h"
#include "Main.h"
#include "usart.h"

#define COMM_STATUS_OK          0
#define COMM_STATUS_BAD_LENGTH  1
#define COMM_STATUS_BAD_PARAM   2
#define COMM_STATUS_BAD_CRC     3
#define COMM_STATUS_DEVICE_ERR  4
#define COMM_STATUS_BUSY        5
#define COMM_STATUS_UNSUPPORTED 6

#define COMM_CMD_PWM_TEST            1
#define COMM_CMD_PING                2
#define COMM_CMD_READ_VOLT_CODE      3
#define COMM_CMD_READ_CURR_CODE      4
#define COMM_CMD_FAN                 5
#define COMM_CMD_SET_OUTER_SETPOINT  6
#define COMM_CMD_SET_SYSTEM_CMD      7
#define COMM_CMD_SET_DIRECTION       9
#define COMM_CMD_SET_MODE_SETPOINT  10
#define COMM_CMD_FAULT_RESET        12
#define COMM_CMD_READ_STATUS_EX     13
#define COMM_CMD_DEVICE_INFO        14

#define COMM_PROTOCOL_MAJOR 2
#define COMM_PROTOCOL_MINOR 0
#define COMM_FIRMWARE_MAJOR 1
#define COMM_FIRMWARE_MINOR 0
#define COMM_FIRMWARE_PATCH 0

#define COMM_CAP_FAN           0x0001
#define COMM_CAP_RAW_ADC       0x0002
#define COMM_CAP_BIDIRECTIONAL 0x0008
#define COMM_CAP_CV_CC         0x0010

TypeCOMM SysComm;

static uint8_t s_fan_enabled = 0;

static uint8_t IsIdle(void)
{
    return (UI.CMD == IDLE) && (UI.State == IDLE);
}

static uint8_t IsSetpointValid(uint8_t mode, float value)
{
    if (mode == CV) return (value >= 2.0f) && (value <= 50.0f);
    if (mode == CC) return (value >= 0.1f) && (value <= 5.0f);
    return 0;
}

static uint8_t ReadU8(uint8_t offset, uint8_t *value)
{
    if (SysComm.RxLen < (uint8_t)(1 + offset + 1 + 2)) return 0;
    *value = SysComm.RxBuf[1 + offset];
    return 1;
}

static uint8_t ReadU16Le(uint8_t offset, uint16_t *value)
{
    if (SysComm.RxLen < (uint8_t)(1 + offset + 2 + 2)) return 0;
    *value = (uint16_t)SysComm.RxBuf[1 + offset] |
             ((uint16_t)SysComm.RxBuf[1 + offset + 1] << 8);
    return 1;
}

static uint8_t ReadFloatLe(uint8_t offset, float *value)
{
    if (SysComm.RxLen < (uint8_t)(1 + offset + sizeof(float) + 2)) return 0;
    memcpy(value, &SysComm.RxBuf[1 + offset], sizeof(float));
    return 1;
}

static void WriteU16Le(uint8_t *buffer, uint8_t *index, uint16_t value)
{
    buffer[(*index)++] = (uint8_t)(value & 0xFF);
    buffer[(*index)++] = (uint8_t)(value >> 8);
}

static void WriteFloatLe(uint8_t *buffer, uint8_t *index, float value)
{
    memcpy(&buffer[*index], &value, sizeof(float));
    *index = (uint8_t)(*index + sizeof(float));
}

static void SendResponse(uint8_t command, uint8_t status,
                         const uint8_t *payload, uint8_t payload_len)
{
    uint8_t tx[96];
    uint8_t index = 0;
    uint8_t crc_high, crc_low;

    tx[index++] = command;
    tx[index++] = status;
    if ((payload != 0) && (payload_len > 0))
    {
        memcpy(&tx[index], payload, payload_len);
        index = (uint8_t)(index + payload_len);
    }
    ModbusCRC16(tx, index, &crc_high, &crc_low);
    tx[index++] = crc_low;
    tx[index++] = crc_high;
    HAL_UART_Transmit(&huart1, tx, index, 100);
}

static void SendAck(uint8_t command, uint8_t status)
{
    SendResponse(command, status, 0, 0);
}

static void HandlePwmTest(void)
{
    uint16_t duty;

    if (!ReadU16Le(0, &duty))
    {
        SendAck(COMM_CMD_PWM_TEST, COMM_STATUS_BAD_LENGTH);
        return;
    }
    if (!IsIdle())
    {
        SendAck(COMM_CMD_PWM_TEST, COMM_STATUS_BUSY);
        return;
    }
    if (duty > PRD)
    {
        SendAck(COMM_CMD_PWM_TEST, COMM_STATUS_BAD_PARAM);
        return;
    }
    if (duty > 0)
    {
        PWM(duty);
        EnablePWM();
    }
    else DisablePWM();
    SendAck(COMM_CMD_PWM_TEST, COMM_STATUS_OK);
}

static void HandleReadVoltageCode(void)
{
    uint8_t payload[8];
    uint8_t index = 0;

    WriteFloatLe(payload, &index, Meter.NewAdcCode[UL]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[UR]);
    SendResponse(COMM_CMD_READ_VOLT_CODE, COMM_STATUS_OK, payload, index);
}

static void HandleReadCurrentCode(void)
{
    uint8_t payload[12];
    uint8_t index = 0;

    WriteFloatLe(payload, &index, Meter.NewAdcCode[IL]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[LIO]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[RIO]);
    SendResponse(COMM_CMD_READ_CURR_CODE, COMM_STATUS_OK, payload, index);
}

static void HandleFan(void)
{
    uint8_t enabled;

    if (!ReadU8(0, &enabled))
    {
        SendAck(COMM_CMD_FAN, COMM_STATUS_BAD_LENGTH);
        return;
    }
    s_fan_enabled = enabled ? 1 : 0;
    if (s_fan_enabled) FAN_SW_H;
    else FAN_SW_L;
    SendAck(COMM_CMD_FAN, COMM_STATUS_OK);
}

static void HandleSetOuterSetpoint(void)
{
    float value;

    if (!ReadFloatLe(0, &value))
    {
        SendAck(COMM_CMD_SET_OUTER_SETPOINT, COMM_STATUS_BAD_LENGTH);
        return;
    }
    if (!IsSetpointValid(UI.RunMode, value))
    {
        SendAck(COMM_CMD_SET_OUTER_SETPOINT, COMM_STATUS_BAD_PARAM);
        return;
    }
    UI.OutLoopSet = value;
    SendAck(COMM_CMD_SET_OUTER_SETPOINT, COMM_STATUS_OK);
}

static void HandleSystemCommand(void)
{
    uint8_t command;

    if (!ReadU8(0, &command))
    {
        SendAck(COMM_CMD_SET_SYSTEM_CMD, COMM_STATUS_BAD_LENGTH);
        return;
    }
    if ((command != RUN) && (command != STOP))
    {
        SendAck(COMM_CMD_SET_SYSTEM_CMD, COMM_STATUS_BAD_PARAM);
        return;
    }
    UI.CMD = command;
    SendAck(COMM_CMD_SET_SYSTEM_CMD, COMM_STATUS_OK);
}

static void HandleDirection(void)
{
    uint8_t direction;

    if (!ReadU8(0, &direction))
    {
        SendAck(COMM_CMD_SET_DIRECTION, COMM_STATUS_BAD_LENGTH);
        return;
    }
    if (!IsIdle())
    {
        SendAck(COMM_CMD_SET_DIRECTION, COMM_STATUS_BUSY);
        return;
    }
    if ((direction != L2R) && (direction != R2L))
    {
        SendAck(COMM_CMD_SET_DIRECTION, COMM_STATUS_BAD_PARAM);
        return;
    }
    UI.DIR = direction;
    SendAck(COMM_CMD_SET_DIRECTION, COMM_STATUS_OK);
}

static void HandleModeSetpoint(void)
{
    uint8_t mode;
    float value;

    if (!ReadU8(0, &mode) || !ReadFloatLe(1, &value))
    {
        SendAck(COMM_CMD_SET_MODE_SETPOINT, COMM_STATUS_BAD_LENGTH);
        return;
    }
    if (!IsIdle())
    {
        SendAck(COMM_CMD_SET_MODE_SETPOINT, COMM_STATUS_BUSY);
        return;
    }
    if (!IsSetpointValid(mode, value))
    {
        SendAck(COMM_CMD_SET_MODE_SETPOINT, COMM_STATUS_BAD_PARAM);
        return;
    }
    UI.RunMode = mode;
    UI.OutLoopSet = value;
    SendAck(COMM_CMD_SET_MODE_SETPOINT, COMM_STATUS_OK);
}

static void HandleStatus(void)
{
    uint8_t payload[68];
    uint8_t index = 0;
    uint8_t fault = (UI.State == FAULT) ? 1 : 0;
    uint16_t duty = (uint16_t)TIM1->CCR1;

    payload[index++] = UI.CMD;
    payload[index++] = UI.State;
    payload[index++] = UI.DIR;
    payload[index++] = UI.RunMode;
    payload[index++] = fault;
    payload[index++] = s_fan_enabled;
    WriteU16Le(payload, &index, duty);
    WriteFloatLe(payload, &index, UI.OutLoopSet);
    WriteFloatLe(payload, &index, UI.SetI);
    WriteFloatLe(payload, &index, UI.ValueOCP);
    WriteFloatLe(payload, &index, Meter.Value[UL]);
    WriteFloatLe(payload, &index, Meter.Value[UR]);
    WriteFloatLe(payload, &index, Meter.Value[IL]);
    WriteFloatLe(payload, &index, Meter.Value[LIO]);
    WriteFloatLe(payload, &index, Meter.Value[RIO]);
    WriteFloatLe(payload, &index, Meter.Value[Ta]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[UL]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[UR]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[IL]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[LIO]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[RIO]);
    WriteFloatLe(payload, &index, Meter.NewAdcCode[Ta]);
    SendResponse(COMM_CMD_READ_STATUS_EX, COMM_STATUS_OK, payload, index);
}

static void HandleDeviceInfo(void)
{
    uint8_t payload[11];
    uint8_t index = 0;
    uint16_t capabilities = COMM_CAP_FAN | COMM_CAP_RAW_ADC |
                            COMM_CAP_BIDIRECTIONAL | COMM_CAP_CV_CC;

    payload[index++] = 'B';
    payload[index++] = 'D';
    payload[index++] = 'C';
    payload[index++] = '2';
    payload[index++] = COMM_PROTOCOL_MAJOR;
    payload[index++] = COMM_PROTOCOL_MINOR;
    payload[index++] = COMM_FIRMWARE_MAJOR;
    payload[index++] = COMM_FIRMWARE_MINOR;
    payload[index++] = COMM_FIRMWARE_PATCH;
    WriteU16Le(payload, &index, capabilities);
    SendResponse(COMM_CMD_DEVICE_INFO, COMM_STATUS_OK, payload, index);
}

void CommInit(void)
{
    SysComm.EOR = 0;
    SysComm.Index = 0;
    SysComm.RxLen = 0;
    s_fan_enabled = 0;
}

void CommProcess(void)
{
    uint8_t command;
    uint8_t crc_high, crc_low;

    if (SysComm.EOR != 1) return;
    SysComm.EOR = 0;
    if (SysComm.RxLen < 3) return;

    ModbusCRC16((uint8_t *)SysComm.RxBuf, SysComm.RxLen - 2,
                &crc_high, &crc_low);
    if ((SysComm.RxBuf[SysComm.RxLen - 2] != crc_low) ||
        (SysComm.RxBuf[SysComm.RxLen - 1] != crc_high))
    {
        return;
    }

    command = SysComm.RxBuf[0];
    switch (command)
    {
        case COMM_CMD_PWM_TEST: HandlePwmTest(); break;
        case COMM_CMD_PING: SendAck(command, COMM_STATUS_OK); break;
        case COMM_CMD_READ_VOLT_CODE: HandleReadVoltageCode(); break;
        case COMM_CMD_READ_CURR_CODE: HandleReadCurrentCode(); break;
        case COMM_CMD_FAN: HandleFan(); break;
        case COMM_CMD_SET_OUTER_SETPOINT: HandleSetOuterSetpoint(); break;
        case COMM_CMD_SET_SYSTEM_CMD: HandleSystemCommand(); break;
        case COMM_CMD_SET_DIRECTION: HandleDirection(); break;
        case COMM_CMD_SET_MODE_SETPOINT: HandleModeSetpoint(); break;
        case COMM_CMD_FAULT_RESET:
            UI.CMD = STOP;
            SendAck(command, COMM_STATUS_OK);
            break;
        case COMM_CMD_READ_STATUS_EX: HandleStatus(); break;
        case COMM_CMD_DEVICE_INFO: HandleDeviceInfo(); break;
        default: SendAck(command, COMM_STATUS_UNSUPPORTED); break;
    }
}

void ModbusCRC16(uint8_t *data, uint16_t len, uint8_t *crc_high,
                 uint8_t *crc_low)
{
    uint16_t crc = 0xFFFF;
    uint16_t i;
    uint8_t j;

    for (i = 0; i < len; i++)
    {
        crc ^= data[i];
        for (j = 0; j < 8; j++)
        {
            if (crc & 0x0001)
            {
                crc >>= 1;
                crc ^= 0xA001;
            }
            else crc >>= 1;
        }
    }
    *crc_high = (uint8_t)(crc >> 8);
    *crc_low = (uint8_t)(crc & 0xFF);
}
