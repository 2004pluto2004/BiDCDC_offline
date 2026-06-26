#include "Feedback.h"
#include "adc.h"
#include "tim.h"

uint16_t AdcValue[AdcNumber] = {0}; //用于反馈信号的采样值
TypeMeter Meter;

void AdcInit(void)
{
	//ADC使能及DMA对应的内存地址配置
	HAL_ADC_Start_DMA(&hadc1, (uint32_t*)AdcValue, 2); //AD1 AD2---ADC1---0 1
	HAL_ADC_Start_DMA(&hadc2, (uint32_t*)(AdcValue+2),2);//AD3 AD4--ADC2--2 3
	HAL_ADC_Start_DMA(&hadc3, (uint32_t*)(AdcValue+4),2); //AD5 AD6--ADC3--4 5
	//TIM3使能
	HAL_TIM_Base_Start(&htim3);
}	

void MeterUpdate()
{
	uint8_t i;
	for(i=0;i<AdcNumber;i++) //处理所有的反馈
	{
		//先进行滤波
		Meter.NewAdcCode[i] =Meter.FilterK[i]*Meter.OldAdcCode[i]+(1-Meter.FilterK[i])*AdcValue[i];
		Meter.OldAdcCode[i] =Meter.NewAdcCode[i];
		//转换成真实的电压或者电流
		Meter.Value[i] =Meter.KB[i].K*Meter.NewAdcCode[i]+Meter.KB[i].B;
	}
}


void MeterInit(void)
{
	uint8_t i;
	//参数初始化
	for(i=0;i<AdcNumber;i++) //所有通道参数初始化
	{
		Meter.FilterK[i] =0.8;
		Meter.OldAdcCode[i] =0;
		Meter.KB[i].K =1;
		Meter.KB[i].B =0;
	}
	//填充实际校准系数
	Meter.KB[UL].K = 0.0128274768;
	Meter.KB[UL].B = 0.0419698987;
	
	Meter.KB[UR].K =0.0127617921;
	Meter.KB[UR].B =0.0096768142;
	
	Meter.KB[IL].K =0.0029066948;
	Meter.KB[IL].B =-6.2830765998;
	
	Meter.KB[LIO].K =0.0029863417;
	Meter.KB[LIO].B =-6.4651013447;
	
	Meter.KB[RIO].K =0.0028051979;
	Meter.KB[RIO].B =-6.0532355652;
	
	AdcInit(); //硬件初始化
}



