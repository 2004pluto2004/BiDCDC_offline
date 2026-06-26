#include "COMM.h"
#include "CommCommands.h"
#include "SerialTransport.h"
#include <string.h>

TypeCOMM SysComm;

void CommInit(void)
{
	SysComm.EOR =0;
	SysComm.Index =0;
	SysComm.RxLen =0;
	SerialTransportInit();
}

void CommProcess(void)
{
	CommFrame frame;
	uint8_t status;

	if(SysComm.EOR!=1) return;
	SysComm.EOR =0;

	status =CommProtocolDecode((uint8_t *)SysComm.RxBuf, SysComm.RxLen, &frame);
	if(status!=COMM_STATUS_OK)
	{
		return;
	}
	CommCommandDispatch(&frame);
}

void CommTransportSend(const uint8_t *data, uint8_t len)
{
	if((data==0)||(len==0)) return;
	SerialTransportSend(data, len);
}

void CommOnRxByte(uint8_t byte)
{
	if(SysComm.Index<BufLen)
	{
		SysComm.RxBuf[SysComm.Index++] =byte;
		return;
	}
	SysComm.Index =0;
}

void CommOnRxIdle(void)
{
	if(SysComm.Index==0)
	{
		return;
	}
	SysComm.RxLen =SysComm.Index;
	SysComm.Index =0;
	SysComm.EOR =1;
}
