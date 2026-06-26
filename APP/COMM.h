#ifndef __COMM_H
#define __COMM_H

#include "stdint.h"
#include "CommProtocol.h"

#define BufLen 128

typedef struct
{
	uint8_t RxBuf[BufLen];
	uint8_t EOR;
	uint8_t RxLen;
	uint8_t Index;
}TypeCOMM;

extern TypeCOMM SysComm;

void CommInit(void);
void CommProcess(void);
void CommTransportSend(const uint8_t *data, uint8_t len);
void CommOnRxByte(uint8_t byte);
void CommOnRxIdle(void);

#endif
