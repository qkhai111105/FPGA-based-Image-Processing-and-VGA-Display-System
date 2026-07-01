#include <stdio.h>
#include <stdint.h>

#include "io.h"
#include "system.h"
#include "sys/alt_irq.h"

enum {
    UART_ADDR_PTR_REG = 0x00,
    VGA_ADDR_PTR_REG = 0x04,
    EDGE_DETECT_WRITE_ADDR_PTR_REG = 0x08,
    EDGE_DETECT_READ_ADDR_PTR_REG = 0x0C,
    INTERRUPT_STATUS_REG = 0x10,
    PERFORM_EDGE_DETECTION_CMD_REG = 0x14
};

enum {
    IRQ_UART_WRAPPED_MASK = 0x01,
    IRQ_EDGE_DETECT_DONE_MASK = 0x02
};

#define IMG_WIDTH       320u
#define IMG_HEIGHT      240u
#define IMG_TOTAL_WORDS (IMG_WIDTH * IMG_HEIGHT)

#define SOURCE_IMG_ADDR        0u
#define EDGE_DETECTED_IMG_ADDR (SOURCE_IMG_ADDR + IMG_TOTAL_WORDS)

static volatile uint32_t uart_frame_count = 0;
static volatile uint32_t edge_done_count = 0;
static volatile int irq_setup_ok = 0;

static inline void custom_write(uint32_t reg_offset, uint32_t value)
{
    IOWR_32DIRECT(CUSTOM_LOGIC_0_BASE, reg_offset, value);
}

static inline uint32_t custom_read(uint32_t reg_offset)
{
    return IORD_32DIRECT(CUSTOM_LOGIC_0_BASE, reg_offset);
}

static void start_edge_detection(void)
{
    custom_write(EDGE_DETECT_READ_ADDR_PTR_REG, SOURCE_IMG_ADDR);
    custom_write(EDGE_DETECT_WRITE_ADDR_PTR_REG, EDGE_DETECTED_IMG_ADDR);
    custom_write(PERFORM_EDGE_DETECTION_CMD_REG, 1u);
}

static void show_edge_frame(void)
{
    custom_write(VGA_ADDR_PTR_REG, EDGE_DETECTED_IMG_ADDR);
}

static void custom_logic_init(void)
{
    custom_write(INTERRUPT_STATUS_REG, 0u);
    custom_write(UART_ADDR_PTR_REG, SOURCE_IMG_ADDR);
    custom_write(VGA_ADDR_PTR_REG, SOURCE_IMG_ADDR);
    custom_write(EDGE_DETECT_READ_ADDR_PTR_REG, SOURCE_IMG_ADDR);
    custom_write(EDGE_DETECT_WRITE_ADDR_PTR_REG, EDGE_DETECTED_IMG_ADDR);
}

static void custom_logic_irq_handler(void *context)
{
    uint32_t status;

    (void)context;

    status = custom_read(INTERRUPT_STATUS_REG);
    custom_write(INTERRUPT_STATUS_REG, 0u);

    if ((status & IRQ_UART_WRAPPED_MASK) != 0u) {
        uart_frame_count++;
        start_edge_detection();
    }

    if ((status & IRQ_EDGE_DETECT_DONE_MASK) != 0u) {
        edge_done_count++;
        show_edge_frame();
    }
}

int main(void)
{
    uint32_t last_uart_frame_count = 0;
    uint32_t last_edge_done_count = 0;
    int result;

    printf("Nios II image pipeline start\n");

    custom_logic_init();

    result = alt_ic_isr_register(
        CUSTOM_LOGIC_0_IRQ_INTERRUPT_CONTROLLER_ID,
        CUSTOM_LOGIC_0_IRQ,
        custom_logic_irq_handler,
        NULL,
        NULL
    );

    irq_setup_ok = (result == 0);
    printf(irq_setup_ok ? "Custom logic ISR registered\n"
                        : "Custom logic ISR registration failed\n");

    while (1) {
        if (last_uart_frame_count != uart_frame_count) {
            last_uart_frame_count = uart_frame_count;
            printf("UART frame received, Sobel started: %lu\n",
                   (unsigned long)last_uart_frame_count);
        }

        if (last_edge_done_count != edge_done_count) {
            last_edge_done_count = edge_done_count;
            printf("Sobel done, VGA switched to edge frame: %lu\n",
                   (unsigned long)last_edge_done_count);
        }
    }

    return 0;
}
