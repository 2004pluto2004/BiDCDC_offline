#include "Control.h"
#include "Feedback.h"
#include "SEGGER_RTT.h"

/*********************RTT相关变量**************************/
uint8_t JS_RTT_UpBuffer[4096]; // J-Scope RTT Buffer
uint16_t JS_RTT_Channel = 1;   // J-Scope RTT Channel
#pragma pack(push, 1)

struct 
{
	int16_t Value1;
	int16_t Value2;
	int16_t Value3;
	int16_t Value4;
	int16_t Value5;
	int16_t Value6;
}JScope;
#pragma pack(pop)

/***********************************************************/

TypeUI UI; //声明系统交互结构体
TypePI VoltagePI,CurrentPI; //声明电压电流控制PI

void PwmInit(void)
{
	PWM(PRD>>1);//占空比初始化为50%
	HAL_TIMEx_PWMN_Start(&htim1, TIM_CHANNEL_1); //使能CH1/CHN
	DisablePWM(); //关闭PWM输出
	HAL_TIM_Base_Start_IT(&htim1);//使能TIM1计数器,并开启中断
}

void ControlInit(void)
{
	//系统参数初始化
	UI.State =IDLE;
	UI.CMD =IDLE;
	UI.ValueOCP =15;
	UI.DelayOCP =3;
	UI.FaultCode =0;
	UI.FanEnabled =0;
	UI.PwmDuty =0;
	UI.DIR =L2R;
	UI.RunMode =CV;
	UI.SetU =15;
	UI.SetI = 1;
	
	//控制参数初始化
	VoltagePI.Kp =0.02;
	VoltagePI.Ki =0.0001;
	VoltagePI.Sum =0;
	VoltagePI.LowLimit =-10;
	VoltagePI.UpLimit =10;
	
	CurrentPI.Kp =50;
	CurrentPI.Ki =1;
	CurrentPI.Sum =0;
	CurrentPI.LowLimit =MinCCR; 
	CurrentPI.UpLimit =MaxCCR; 
	
	//RTT初始化
	SEGGER_RTT_ConfigUpBuffer(JS_RTT_Channel, "JScope_i2i2i2i2i2i2", \
	&JS_RTT_UpBuffer[0], sizeof(JS_RTT_UpBuffer), SEGGER_RTT_MODE_NO_BLOCK_SKIP);
}
	
void StateMachine(void)
{
	if(UI.CMD==IDLE) return; //系统等待
	if(UI.CMD==RUN) 
	{
		if(UI.State==IDLE)
		{
			EnablePWM();
			UI.State =RUN;
		}
		else if(UI.State==RUN)
		{
			Control();//运行闭环控制程序
			if(UI.State==FAULT)
			{
				DisablePWM(); //关掉PWM输出
				UI.FaultCode =1;
				UI.CMD =STOP;
			}
		}
	}
	if(UI.CMD==STOP) //停机指令
	{
		DisablePWM(); //关掉PWM输出
		ControlInit();//参数重新初始化
		UI.CMD =IDLE; //回到空闲状态
		UI.State =IDLE; //关机复位状态
	}
}

void Control(void)
{
	float I_L,Uo;
	//读取电感电流时,注意方向
	if(UI.DIR==L2R)
	{
		I_L =-Meter.Value[IL];
	   Uo =Meter.Value[UR];
	}
	else
	{
		I_L =Meter.Value[IL];
	   Uo =Meter.Value[UL];
	}
	
	//首先做过流保护
	if((I_L>UI.ValueOCP)||(I_L<-UI.ValueOCP))
	{
		UI.CountOCP++;
		if(UI.CountOCP>=UI.DelayOCP) //检测到过流立即退出
		{
			UI.State =FAULT; //故障标志
			UI.FaultCode =1;
			return;
		}
	}
	else UI.CountOCP =0;
	
	//恒压模式下通过计算电压环得到电流环的指令值
	if(UI.RunMode==CV) 
	{
		VoltagePI.Reference =UI.SetU;
		VoltagePI.FeedBack =Uo;
		RunPI(&VoltagePI);
		UI.SetI =VoltagePI.Output;
	}
   //运行电流环
	if(UI.DIR==R2L)//电感电流与占空比负相关,因此控制环路上要加一个负号
	{
		//通过指令与反馈交换实现加负号
		CurrentPI.Reference =UI.SetI;
		CurrentPI.FeedBack =I_L;
	}
	else//电感电流与占空比正相关,正常控制
	{	
		CurrentPI.Reference =I_L;
		CurrentPI.FeedBack =UI.SetI;
	}
	RunPI(&CurrentPI); //计算新的占空比
	UI.PwmDuty =(uint16_t)CurrentPI.Output;
	PWM(UI.PwmDuty); //刷新占空比输出
	
	//输出示波器观察
	JScope.Value1 =(int16_t)(VoltagePI.Reference*100);
	JScope.Value2 =(int16_t)(VoltagePI.FeedBack*100);
	JScope.Value3 =(int16_t)(VoltagePI.Error*100);
	JScope.Value4 =(int16_t)(CurrentPI.Reference*1000);
	JScope.Value5 =(int16_t)(CurrentPI.FeedBack*1000);
	JScope.Value6 =(int16_t)(CurrentPI.Error*1000);
	
	SEGGER_RTT_Write(JS_RTT_Channel, &JScope, sizeof(JScope));
}


void RunPI(TypePI *P)
{
	//计算误差
	P->Error =P->Reference-P->FeedBack;
	//计算比例部分
	float KpPart =P->Kp*P->Error;
	//计算积分部分
	P->Sum +=P->Ki*P->Error;
	//积分限幅
	if(P->Sum>P->UpLimit) P->Sum =P->UpLimit;
	else if(P->Sum<P->LowLimit) P->Sum =P->LowLimit;
	//计算总输出
	P->Output =KpPart+P->Sum;
	//总限幅
	if(P->Output>P->UpLimit) P->Output =P->UpLimit;
	else if(P->Output<P->LowLimit) P->Output =P->LowLimit;
}

