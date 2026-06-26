#include "CommProtocol.h"
#include <string.h>
#include "COMM.h"
#include "usart.h"

uint8_t CommProtocolDecode(const uint8_t *rx, uint8_t rx_len, CommFrame *frame)
{
	uint8_t crc_high, crc_low;

	if((rx==0)||(frame==0)||(rx_len<3)) return COMM_STATUS_BAD_LENGTH;
	ModbusCRC16((uint8_t *)rx, rx_len-2, &crc_high, &crc_low);
	if((rx[rx_len-2]!=crc_low)||(rx[rx_len-1]!=crc_high)) return COMM_STATUS_BAD_CRC;
	frame->command =rx[0];
	frame->payload =rx+1;
	frame->payload_len =rx_len-3;
	return COMM_STATUS_OK;
}

void CommProtocolSendResponse(uint8_t cmd, uint8_t status, const uint8_t *payload, uint8_t payload_len)
{
	uint8_t tx[BufLen];
	uint8_t crc_high, crc_low;
	uint16_t frame_len;

	if(payload_len>(BufLen-4)) payload_len =BufLen-4;
	tx[0] =cmd;
	tx[1] =status;
	if((payload!=0)&&(payload_len>0))
	{
		memcpy(tx+2, payload, payload_len);
	}
	ModbusCRC16(tx, payload_len+2, &crc_high, &crc_low);
	tx[payload_len+2] =crc_low;
	tx[payload_len+3] =crc_high;
	frame_len =payload_len+4;
	CommTransportSend(tx, frame_len);
}

void CommProtocolSendAck(uint8_t cmd, uint8_t status)
{
	CommProtocolSendResponse(cmd, status, 0, 0);
}

uint8_t CommReadU8(const CommFrame *frame, uint8_t offset, uint8_t *value)
{
	if((frame==0)||(value==0)||(frame->payload_len<(offset+1))) return 0;
	*value =frame->payload[offset];
	return 1;
}

uint8_t CommReadU16Le(const CommFrame *frame, uint8_t offset, uint16_t *value)
{
	if((frame==0)||(value==0)||(frame->payload_len<(offset+2))) return 0;
	*value =(uint16_t)frame->payload[offset] | ((uint16_t)frame->payload[offset+1]<<8);
	return 1;
}

uint8_t CommReadFloatLe(const CommFrame *frame, uint8_t offset, float *value)
{
	if((frame==0)||(value==0)||(frame->payload_len<(offset+sizeof(float)))) return 0;
	memcpy(value, frame->payload+offset, sizeof(float));
	return 1;
}

void CommWriteU16Le(uint8_t *buf, uint8_t *index, uint16_t value)
{
	buf[(*index)++] =(uint8_t)(value&0xFF);
	buf[(*index)++] =(uint8_t)(value>>8);
}

void CommWriteFloatLe(uint8_t *buf, uint8_t *index, float value)
{
	memcpy(buf+(*index), &value, sizeof(float));
	*index +=sizeof(float);
}

void ModbusCRC16(uint8_t *data, uint16_t len, uint8_t *crc_high, uint8_t *crc_low)
{
	uint16_t crc =0xFFFF;
	uint8_t i, j;

	for(i=0;i<len;i++)
	{
		crc ^=data[i];
		for(j=0;j<8;j++)
		{
			if(crc&0x0001)
			{
				crc >>=1;
				crc ^=0xA001;
			}
			else crc >>=1;
		}
	}
	*crc_high =(uint8_t)(crc>>8);
	*crc_low =(uint8_t)(crc&0xFF);
}
