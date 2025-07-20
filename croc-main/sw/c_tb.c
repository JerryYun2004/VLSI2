#include "uart.h"
#include "print.h"
#include "gpio.h"
#include "util.h"
#include "config.h"
#include <stdint.h>

#define CNN_BASE_ADDR          0x20001000
#define CNN_CTRL_REG           0x00
#define CNN_STATUS_REG         0x04
#define CNN_CLASS_IDX_REG      0x14
#define CNN_PIXEL_IN_REG       0x18
#define CNN_CLASS_SCORES_BASE  0x20

#define SRAM_BASE              0x10000000
#define IMAGE_OFFSET           0x0A00

#define USER_FINISH_ADDR       0x03000008
#define USER_FINISH_VALUE      0xCAFEDEAD

volatile uint32_t status = 0;

void print_stack_pointer() {
    uint32_t sp_val;
    asm volatile ("mv %0, sp" : "=r"(sp_val));
    printf("Initial SP: 0x%x\n", sp_val);
    uart_write_flush();
}

int main() {
    uart_init();
    print_stack_pointer();

    printf("Starting CNN accelerator test for all classes.\n");
    uart_write_flush();

    uint32_t t0, t1, t2;
    uint32_t* image_base = (uint32_t*)(SRAM_BASE + IMAGE_OFFSET);

    asm volatile("csrr %0, mcycle" : "=r"(t0)::"memory");

    for (int class_idx = 0; class_idx < 10; class_idx++) {
        printf("Processing for class index: %x\n", class_idx);
        uart_write_flush();

        // Set class index
        *reg32(CNN_BASE_ADDR, CNN_CLASS_IDX_REG) = class_idx;

        for (int i = 0; i < 784; i++) {
            uint8_t pixel = *((uint8_t*)(SRAM_BASE + IMAGE_OFFSET + i));
            *reg32(CNN_BASE_ADDR, CNN_PIXEL_IN_REG) = pixel;
            if (i < 10) { // only print first few pixels to limit UART spam
                printf("Pixel[%d] = %d\n", i, pixel);
            }
        }
        uart_write_flush();
        // Trigger processing
        *reg32(CNN_BASE_ADDR, CNN_CTRL_REG) = 1;

        // Wait for completion
        while (*reg32(CNN_BASE_ADDR, CNN_STATUS_REG) == 0);

        printf("Class %x: Processing completed.\n", class_idx);
        uart_write_flush();
    }

    asm volatile("csrr %0, mcycle" : "=r"(t1)::"memory");

    printf("Reading CNN output scores per class:\n");
    uart_write_flush();

    for (int class_idx = 0; class_idx < 10; class_idx++) {
        uint32_t addr = CNN_BASE_ADDR + CNN_CLASS_SCORES_BASE + (class_idx * 4);
        uint32_t score = *reg32(addr, 0);

        printf("Class %x accumulated score: %x\n", class_idx, score);
        uart_write_flush();
    }

    asm volatile("csrr %0, mcycle" : "=r"(t2)::"memory");

    printf("Performance: Processing time = %x cycles, Output read time = %x cycles\n", t1 - t0, t2 - t1);
    uart_write_flush();

    printf("CNN processing complete. Writing finish code.\n");
    uart_write_flush();

    return USER_FINISH_VALUE;
}
