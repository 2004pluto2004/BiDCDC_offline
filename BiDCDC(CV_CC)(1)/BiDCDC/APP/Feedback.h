#ifndef __FEEDBACK_H
#define __FEEDBACK_H

#define AdcNumber 6 //ADC采样信号数量
//反馈信号映射
#define IL 0
#define UR 1
#define LIO 2
#define RIO 3
#define UL 4
#define Ta 5


typedef struct
{
	float K;
	float B;
}TypeKB;

typedef struct
{
	float FilterK[AdcNumber]; //滤波系数
	float OldAdcCode[AdcNumber]; //上一拍的ADC值
	float NewAdcCode[AdcNumber]; //当先ADC值
	TypeKB KB[AdcNumber]; //ADC转换成真实值的系数,最好通过校准
	float Value[AdcNumber];//真实值
}TypeMeter;

extern TypeMeter Meter;

void AdcInit(void);//采样对应ADC初始化
void MeterUpdate(void);//刷新所有反馈信号
void MeterInit(void); //反馈初始化(含ADC信号链初始化)

#endif