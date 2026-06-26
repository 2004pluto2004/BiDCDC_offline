#ifndef __COMM_PROTOCOL_H
#define __COMM_PROTOCOL_H

#include "stdint.h"

#define COMM_CMD_PWM_TEST          1
#define COMM_CMD_PING              2
#define COMM_CMD_READ_VOLT_CODE    3
#define COMM_CMD_READ_CURR_CODE    4
#define COMM_CMD_FAN               5
#define COMM_CMD_SET_VOLTAGE       6
#define COMM_CMD_SET_SYSTEM_CMD    7
#define COMM_CMD_SET_CURRENT       8
#define COMM_CMD_SET_DIRECTION     9
#define COMM_CMD_SET_RUN_MODE      10
#define COMM_CMD_READ_STATUS       11
#define COMM_CMD_FAULT_RESET       12
#define COMM_CMD_READ_STATUS_EX    13
#define COMM_CMD_SET_PID           32
#define COMM_CMD_READ_PID          33
#define COMM_CMD_READ_WAVEFORM     48

#define COMM_STATUS_OK             0
#define COMM_STATUS_BAD_LENGTH     1
#define COMM_STATUS_BAD_PARAM      2
#define COMM_STATUS_BAD_CRC        3
#define COMM_STATUS_DEVICE_ERROR   4

#define COMM_PID_VOLTAGE_LOOP      0
#define COMM_PID_CURRENT_LOOP      1

#define COMM_WAVEFORM_CH_COUNT     6
#define COMM_STATUS_LEGACY_PAYLOAD_LEN 28
#define COMM_STATUS_EX_PAYLOAD_LEN     64

typedef struct
{
	uint8_t command;
	const uint8_t *payload;
	uint8_t payload_len;
}CommFrame;

void ModbusCRC16(uint8_t *data, uint16_t len, uint8_t *crc_high, uint8_t *crc_low);
uint8_t CommProtocolDecode(const uint8_t *rx, uint8_t rx_len, CommFrame *frame);
void CommProtocolSendResponse(uint8_t cmd, uint8_t status, const uint8_t *payload, uint8_t payload_len);
void CommProtocolSendAck(uint8_t cmd, uint8_t status);
uint8_t CommReadU8(const CommFrame *frame, uint8_t offset, uint8_t *value);
uint8_t CommReadU16Le(const CommFrame *frame, uint8_t offset, uint16_t *value);
uint8_t CommReadFloatLe(const CommFrame *frame, uint8_t offset, float *value);
void CommWriteU16Le(uint8_t *buf, uint8_t *index, uint16_t value);
void CommWriteFloatLe(uint8_t *buf, uint8_t *index, float value);

#endif
