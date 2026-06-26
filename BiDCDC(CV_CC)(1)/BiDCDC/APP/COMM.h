#ifndef __COMM_H
#define __COMM_H

#include "stdint.h"

#define BufLen 128

typedef struct
{
    uint8_t RxBuf[BufLen];
    volatile uint8_t EOR;
    volatile uint8_t RxLen;
    volatile uint8_t Index;
} TypeCOMM;

extern TypeCOMM SysComm;

void CommInit(void);
void CommProcess(void);
void ModbusCRC16(uint8_t *data, uint16_t len, uint8_t *crc_high,
                 uint8_t *crc_low);

#endif
