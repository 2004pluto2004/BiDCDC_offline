#include "CommCommands.h"
#include "Control.h"
#include "Feedback.h"
#include "Main.h"
#include <stdio.h>

static TypePI *CommSelectPid(uint8_t loop);
static void CommHandlePwmTest(const CommFrame *frame);
static void CommHandleFan(const CommFrame *frame);
static void CommHandleReadVoltCode(const CommFrame *frame);
static void CommHandleReadCurrCode(const CommFrame *frame);
static void CommHandleSetVoltage(const CommFrame *frame);
static void CommHandleSetSystemCommand(const CommFrame *frame);
static void CommHandleSetCurrent(const CommFrame *frame);
static void CommHandleSetDirection(const CommFrame *frame);
static void CommHandleSetRunMode(const CommFrame *frame);
static void CommHandleFaultReset(const CommFrame *frame);
static void CommHandleReadStatus(const CommFrame *frame);
static void CommHandleReadStatusEx(const CommFrame *frame);
static void CommHandleSetPid(const CommFrame *frame);
static void CommHandleReadPid(const CommFrame *frame);
static void CommHandleReadWaveform(const CommFrame *frame);

void CommCommandDispatch(const CommFrame *frame)
{
	switch(frame->command)
	{
		case COMM_CMD_PWM_TEST:
			CommHandlePwmTest(frame);
			break;
		case COMM_CMD_PING:
			printf("ACK !!\n");
			break;
		case COMM_CMD_READ_VOLT_CODE:
			CommHandleReadVoltCode(frame);
			break;
		case COMM_CMD_READ_CURR_CODE:
			CommHandleReadCurrCode(frame);
			break;
		case COMM_CMD_FAN:
			CommHandleFan(frame);
			break;
		case COMM_CMD_SET_VOLTAGE:
			CommHandleSetVoltage(frame);
			break;
		case COMM_CMD_SET_SYSTEM_CMD:
			CommHandleSetSystemCommand(frame);
			break;
		case COMM_CMD_SET_CURRENT:
			CommHandleSetCurrent(frame);
			break;
		case COMM_CMD_SET_DIRECTION:
			CommHandleSetDirection(frame);
			break;
		case COMM_CMD_SET_RUN_MODE:
			CommHandleSetRunMode(frame);
			break;
		case COMM_CMD_READ_STATUS:
			CommHandleReadStatus(frame);
			break;
		case COMM_CMD_FAULT_RESET:
			CommHandleFaultReset(frame);
			break;
		case COMM_CMD_READ_STATUS_EX:
			CommHandleReadStatusEx(frame);
			break;
		case COMM_CMD_SET_PID:
			CommHandleSetPid(frame);
			break;
		case COMM_CMD_READ_PID:
			CommHandleReadPid(frame);
			break;
		case COMM_CMD_READ_WAVEFORM:
			CommHandleReadWaveform(frame);
			break;
		default:
			CommProtocolSendAck(frame->command, COMM_STATUS_BAD_PARAM);
			break;
	}
}

static TypePI *CommSelectPid(uint8_t loop)
{
	if(loop==COMM_PID_VOLTAGE_LOOP) return &VoltagePI;
	if(loop==COMM_PID_CURRENT_LOOP) return &CurrentPI;
	return 0;
}

static void CommHandlePwmTest(const CommFrame *frame)
{
	uint16_t duty;

	if(!CommReadU16Le(frame, 0, &duty))
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
		return;
	}
	UI.PwmDuty =duty;
	if(duty>0)
	{
		EnablePWM();
		PWM(duty);
	}
	else DisablePWM();
	CommProtocolSendAck(frame->command, COMM_STATUS_OK);
}

static void CommHandleFan(const CommFrame *frame)
{
	uint8_t enabled;

	if(!CommReadU8(frame, 0, &enabled))
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
		return;
	}
	UI.FanEnabled =enabled ? 1 : 0;
	if(UI.FanEnabled) FAN_SW_H;
	else FAN_SW_L;
	CommProtocolSendAck(frame->command, COMM_STATUS_OK);
}

static void CommHandleReadVoltCode(const CommFrame *frame)
{
	uint8_t payload[2*sizeof(float)];
	uint8_t index =0;

	CommWriteFloatLe(payload, &index, Meter.NewAdcCode[UL]);
	CommWriteFloatLe(payload, &index, Meter.NewAdcCode[UR]);
	CommProtocolSendResponse(frame->command, COMM_STATUS_OK, payload, index);
}

static void CommHandleReadCurrCode(const CommFrame *frame)
{
	uint8_t payload[3*sizeof(float)];
	uint8_t index =0;

	CommWriteFloatLe(payload, &index, Meter.NewAdcCode[IL]);
	CommWriteFloatLe(payload, &index, Meter.NewAdcCode[LIO]);
	CommWriteFloatLe(payload, &index, Meter.NewAdcCode[RIO]);
	CommProtocolSendResponse(frame->command, COMM_STATUS_OK, payload, index);
}

static void CommHandleSetVoltage(const CommFrame *frame)
{
	float value;

	if(CommReadFloatLe(frame, 0, &value))
	{
		UI.SetU =value;
		CommProtocolSendAck(frame->command, COMM_STATUS_OK);
	}
	else CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
}

static void CommHandleSetSystemCommand(const CommFrame *frame)
{
	uint8_t cmd;

	if(!CommReadU8(frame, 0, &cmd))
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
		return;
	}
	if((cmd!=IDLE)&&(cmd!=RUN)&&(cmd!=STOP)&&(cmd!=FAULT))
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_PARAM);
		return;
	}
	UI.CMD =cmd;
	CommProtocolSendAck(frame->command, COMM_STATUS_OK);
}

static void CommHandleSetCurrent(const CommFrame *frame)
{
	float value;

	if(CommReadFloatLe(frame, 0, &value))
	{
		UI.SetI =value;
		CommProtocolSendAck(frame->command, COMM_STATUS_OK);
	}
	else CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
}

static void CommHandleSetDirection(const CommFrame *frame)
{
	uint8_t direction;

	if(!CommReadU8(frame, 0, &direction)) CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
	else if((direction!=L2R)&&(direction!=R2L)) CommProtocolSendAck(frame->command, COMM_STATUS_BAD_PARAM);
	else
	{
		UI.DIR =direction;
		CommProtocolSendAck(frame->command, COMM_STATUS_OK);
	}
}

static void CommHandleSetRunMode(const CommFrame *frame)
{
	uint8_t mode;

	if(!CommReadU8(frame, 0, &mode)) CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
	else if((mode!=CV)&&(mode!=CC)) CommProtocolSendAck(frame->command, COMM_STATUS_BAD_PARAM);
	else
	{
		UI.RunMode =mode;
		CommProtocolSendAck(frame->command, COMM_STATUS_OK);
	}
}

static void CommHandleFaultReset(const CommFrame *frame)
{
	(void)frame;
	UI.CMD =IDLE;
	UI.State =IDLE;
	UI.FaultCode =0;
	UI.CountOCP =0;
	DisablePWM();
	CommProtocolSendAck(COMM_CMD_FAULT_RESET, COMM_STATUS_OK);
}

static void CommHandleReadStatus(const CommFrame *frame)
{
	uint8_t payload[COMM_STATUS_LEGACY_PAYLOAD_LEN];
	uint8_t index =0;

	payload[index++] =UI.CMD;
	payload[index++] =UI.State;
	payload[index++] =UI.DIR;
	payload[index++] =UI.RunMode;
	CommWriteFloatLe(payload, &index, UI.SetU);
	CommWriteFloatLe(payload, &index, UI.SetI);
	CommWriteFloatLe(payload, &index, UI.ValueOCP);
	CommWriteFloatLe(payload, &index, Meter.Value[UL]);
	CommWriteFloatLe(payload, &index, Meter.Value[UR]);
	CommWriteFloatLe(payload, &index, Meter.Value[IL]);
	CommProtocolSendResponse(frame->command, COMM_STATUS_OK, payload, index);
}

static void CommHandleReadStatusEx(const CommFrame *frame)
{
	uint8_t payload[COMM_STATUS_EX_PAYLOAD_LEN];
	uint8_t index =0;
	uint8_t i;

	payload[index++] =UI.CMD;
	payload[index++] =UI.State;
	payload[index++] =UI.DIR;
	payload[index++] =UI.RunMode;
	payload[index++] =UI.FaultCode;
	payload[index++] =UI.FanEnabled;
	CommWriteU16Le(payload, &index, UI.PwmDuty);
	CommWriteFloatLe(payload, &index, UI.SetU);
	CommWriteFloatLe(payload, &index, UI.SetI);
	CommWriteFloatLe(payload, &index, UI.ValueOCP);
	CommWriteFloatLe(payload, &index, Meter.Value[UL]);
	CommWriteFloatLe(payload, &index, Meter.Value[UR]);
	CommWriteFloatLe(payload, &index, Meter.Value[IL]);
	CommWriteFloatLe(payload, &index, Meter.Value[LIO]);
	CommWriteFloatLe(payload, &index, Meter.Value[RIO]);
	for(i=0;i<AdcNumber;i++)
	{
		CommWriteFloatLe(payload, &index, Meter.NewAdcCode[i]);
	}
	CommProtocolSendResponse(frame->command, COMM_STATUS_OK, payload, index);
}

static void CommHandleSetPid(const CommFrame *frame)
{
	uint8_t loop;
	float kp, ki;
	TypePI *pid;

	if(!CommReadU8(frame, 0, &loop)||!CommReadFloatLe(frame, 1, &kp)||!CommReadFloatLe(frame, 5, &ki))
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
		return;
	}
	pid =CommSelectPid(loop);
	if(pid==0)
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_PARAM);
		return;
	}
	pid->Kp =kp;
	pid->Ki =ki;
	CommProtocolSendAck(frame->command, COMM_STATUS_OK);
}

static void CommHandleReadPid(const CommFrame *frame)
{
	uint8_t payload[9];
	uint8_t index =0;
	uint8_t loop;
	TypePI *pid;

	if(!CommReadU8(frame, 0, &loop))
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_LENGTH);
		return;
	}
	pid =CommSelectPid(loop);
	if(pid==0)
	{
		CommProtocolSendAck(frame->command, COMM_STATUS_BAD_PARAM);
		return;
	}
	payload[index++] =loop;
	CommWriteFloatLe(payload, &index, pid->Kp);
	CommWriteFloatLe(payload, &index, pid->Ki);
	CommProtocolSendResponse(frame->command, COMM_STATUS_OK, payload, index);
}

static void CommHandleReadWaveform(const CommFrame *frame)
{
	uint8_t payload[COMM_WAVEFORM_CH_COUNT*sizeof(float)];
	uint8_t index =0;

	CommWriteFloatLe(payload, &index, VoltagePI.Reference);
	CommWriteFloatLe(payload, &index, VoltagePI.FeedBack);
	CommWriteFloatLe(payload, &index, VoltagePI.Error);
	CommWriteFloatLe(payload, &index, CurrentPI.Reference);
	CommWriteFloatLe(payload, &index, CurrentPI.FeedBack);
	CommWriteFloatLe(payload, &index, CurrentPI.Error);
	CommProtocolSendResponse(frame->command, COMM_STATUS_OK, payload, index);
}
