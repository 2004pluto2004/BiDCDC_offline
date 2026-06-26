#include "SerialTransport.h"
#include "usart.h"

void SerialTransportInit(void)
{
	__HAL_UART_ENABLE_IT(&huart1, UART_IT_IDLE);
	__HAL_UART_ENABLE_IT(&huart1, UART_IT_RXNE);
}

void SerialTransportSend(const uint8_t *data, uint8_t len)
{
	if((data==0)||(len==0)) return;
	HAL_UART_Transmit(&huart1, (uint8_t *)data, len, 0xFFFF);
}
