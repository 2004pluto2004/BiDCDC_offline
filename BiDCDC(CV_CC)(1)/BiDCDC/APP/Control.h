#ifndef __CONTROL_H
#define __CONTROL_H
#include "stdint.h"
#include "tim.h"

#define PRD 2100 //定时器重载值--对应100%占空比 //4200--25kHz  2100--50kHz
#define MaxCCR PRD-100 //最大的比较值--对应最大占空比=MaxCCR/PRD
#define MinCCR 100  //最大的比较值--对应最大占空比=MinCCR/PRD

#define EnablePWM()  (TIM1->CCER |=(TIM_CCER_CC1E | TIM_CCER_CC1NE)) //使能PWM输出
#define DisablePWM() (TIM1->CCER &=~(TIM_CCER_CC1E | TIM_CCER_CC1NE)) //关闭PWM输出
#define PWM(Duty) (TIM1->CCR1 =(Duty)) //设置PWM波的转空比

//功率方向选项
#define L2R 0
#define R2L 1

//运行模式选项
#define CV 0 //Const Voltage--恒压模式
#define CC 1 //Const Current--恒流模式

//CMD或者系统状态的选项
#define IDLE   0
#define RUN    1
#define STOP   2
#define FAULT  3


typedef struct
{
	uint8_t DIR;//功率方向设定
	uint8_t RunMode; //运行模式
	float OutLoopSet; //外环参考值:电压单位是V,电流单位是A
	float SetI; //电感电压设定值,A
	uint8_t CMD; //指令
	uint8_t State; //用于记录系统状态
	float ValueOCP; //过流保护设定值,A
	uint8_t CountOCP; //过流检测确认计数
	uint8_t DelayOCP; //过流故障确定阈值
}TypeUI;


//PI控制结构体定义
typedef struct
{
	float Reference; //给定
	float FeedBack;  //反馈
	float Error;     //误差
	float Kp;        //比例系数
	float Ki;        //积分系数
	float Sum;       //积分累加值
	float UpLimit;   //输出上限幅
	float LowLimit;  //输出下限幅
	float Output;    //控制器输出
}TypePI;

extern TypeUI UI;

void PwmInit(void); //开启PWM产生时序
void StateMachine(void);//系统状态机
void Control(void); //系统闭环控制
void ControlInit(void); //系统控制变量初始化
void RunPI(TypePI *P);


#endif