#ifndef __SERIAL_TRANSPORT_H
#define __SERIAL_TRANSPORT_H

#include "stdint.h"

void SerialTransportInit(void);
void SerialTransportSend(const uint8_t *data, uint8_t len);

#endif
