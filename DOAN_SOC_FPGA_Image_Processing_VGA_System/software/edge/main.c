/*
 * "Hello World" example.
 *
 * This example prints 'Hello from Nios II' to the STDOUT stream. It runs on
 * the Nios II 'standard', 'full_featured', 'fast', and 'low_cost' example
 * designs. It runs with or without the MicroC/OS-II RTOS and requires a STDOUT
 * device in your system's hardware.
 * The memory footprint of this hosted application is ~69 kbytes by default
 * using the standard reference design.
 *
 * For a reduced footprint version of this template, and an explanation of how
 * to reduce the memory footprint for a given application, see the
 * "small_hello_world" template.
 *
 */

#include <stdio.h>
#include "system.h"
#include "io.h"
#include "sys/alt_irq.h"
#include "stdint.h"

#define UART_ADDR_PTR 					0x0000
#define VGA_ADDR_PTR 					0x0004
#define EDGE_DETECT_WRITE_ADDR_PTR		0x0008
#define EDGE_DETECT_READ_ADDR_PTR		0x000C
#define INTERRUPT_STATUS_REG			0x0010
#define PERFORM_EDGE_DETECTION_CMD		0x0014
#define IRQ_UART_WRAPPED_MASK			0x0001
#define IRQ_EDGE_DETECT_DONE_MASK		0x0002
#define IMG_TOTAL_WORDS					76800
#define SOURCE_IMG_ADDR					0
#define EDGE_DETECTED_IMG_ADDR			(SOURCE_IMG_ADDR + IMG_TOTAL_WORDS * 1)

void uart_wrapped_handler(){
	printf("uart wrapped handler invoked\n");
	// setup edge detect read and write ptr
	IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, EDGE_DETECT_READ_ADDR_PTR, SOURCE_IMG_ADDR);
	IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, EDGE_DETECT_WRITE_ADDR_PTR, EDGE_DETECTED_IMG_ADDR);

	// send perform edge detection cmd
	IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, PERFORM_EDGE_DETECTION_CMD, 1);
}

void edge_detect_done_handler(){
	printf("edge detect done handler invoked\n");
	// switch vga ptr to edge detected img
	IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, VGA_ADDR_PTR, EDGE_DETECTED_IMG_ADDR);
}

void custom_logic_irq_handler(void* context){
	// read the status register
	uint32_t isr_reg = IORD_32DIRECT(CUSTOM_LOGIC_0_BASE, INTERRUPT_STATUS_REG);

	// clear irs status register
	IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, INTERRUPT_STATUS_REG, 0);

	// call uart wrap handler when hit irq bit
	if (isr_reg & IRQ_UART_WRAPPED_MASK){
		uart_wrapped_handler();
	}

	// call edge detect done handler when hit irq bit
	if (isr_reg & IRQ_EDGE_DETECT_DONE_MASK){
		edge_detect_done_handler();
	}
}

void custom_logic_init(){
	// reset uart and vga ptr
	IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, UART_ADDR_PTR, SOURCE_IMG_ADDR);
	IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, VGA_ADDR_PTR, SOURCE_IMG_ADDR);
}

int main()
{
  printf("Hello from Nios II!\n");

  custom_logic_init();

  // register custom logic irq
  int result = alt_ic_isr_register(
		  CUSTOM_LOGIC_0_IRQ_INTERRUPT_CONTROLLER_ID,
		  CUSTOM_LOGIC_0_IRQ,
		  custom_logic_irq_handler,
		  NULL,
		  0x00
  );

  if (result == 0) {
          printf("ISR Registered Successfully!\n");
  }
  else {
          printf("ISR Registration Failed!\n");
  }

  /* debug
  IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, EDGE_DETECT_READ_ADDR_PTR, EDGE_DETECTED_IMG_ADDR);

  int test = IORD_32DIRECT(CUSTOM_LOGIC_0_BASE, EDGE_DETECT_READ_ADDR_PTR);

  printf("test: %d\n", test);
  */

  while (1){

  }

  return 0;
}
