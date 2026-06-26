/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    stm32f4xx_it.c
  * @brief   Interrupt Service Routines.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

#include "main.h"
#include "stm32f4xx_it.h"

/* USER CODE BEGIN Includes */
#include "COMM.h"
/* USER CODE END Includes */

extern TIM_HandleTypeDef htim1;
extern UART_HandleTypeDef huart1;

void NMI_Handler(void)
{
  while (1)
  {
  }
}

void HardFault_Handler(void)
{
  while (1)
  {
  }
}

void MemManage_Handler(void)
{
  while (1)
  {
  }
}

void BusFault_Handler(void)
{
  while (1)
  {
  }
}

void UsageFault_Handler(void)
{
  while (1)
  {
  }
}

void SVC_Handler(void)
{
}

void DebugMon_Handler(void)
{
}

void PendSV_Handler(void)
{
}

void SysTick_Handler(void)
{
  HAL_IncTick();
}

void TIM1_UP_TIM10_IRQHandler(void)
{
  HAL_TIM_IRQHandler(&htim1);
}

void USART1_IRQHandler(void)
{
  uint32_t temp;

  if (__HAL_UART_GET_FLAG(&huart1, UART_FLAG_RXNE) &&
      __HAL_UART_GET_IT_SOURCE(&huart1, UART_IT_RXNE))
  {
    CommOnRxByte((uint8_t)(huart1.Instance->DR & 0x00FF));
  }

  if (__HAL_UART_GET_FLAG(&huart1, UART_FLAG_IDLE) &&
      __HAL_UART_GET_IT_SOURCE(&huart1, UART_IT_IDLE))
  {
    temp = huart1.Instance->SR;
    temp = huart1.Instance->DR;
    (void)temp;
    CommOnRxIdle();
  }

  if (__HAL_UART_GET_FLAG(&huart1, UART_FLAG_ORE))
  {
    __HAL_UART_CLEAR_OREFLAG(&huart1);
  }
  if (__HAL_UART_GET_FLAG(&huart1, UART_FLAG_FE))
  {
    __HAL_UART_CLEAR_FEFLAG(&huart1);
  }
  if (__HAL_UART_GET_FLAG(&huart1, UART_FLAG_NE))
  {
    __HAL_UART_CLEAR_NEFLAG(&huart1);
  }
}
