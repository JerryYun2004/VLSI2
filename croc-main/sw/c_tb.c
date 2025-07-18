#include "uart.h"
#include "print.h"
#include "gpio.h"
#include "util.h"
#include "config.h"
#include <stdint.h>

#define CNN_BASE_ADDR          0x20001000
#define CNN_CTRL_REG           0x00
#define CNN_STATUS_REG         0x04
#define CNN_INPUT_BASE_REG     0x08
#define CNN_WEIGHT_BASE_REG    0x10
#define CNN_CLASS_IDX_REG      0x14
#define CNN_CLASS_SCORES_BASE  0x20

#define SRAM_BASE              0x10000000
#define IMAGE_OFFSET           0x0A00

#define USER_FINISH_ADDR       0x03000008
#define USER_FINISH_VALUE      0xCAFEDEAD

volatile uint32_t status = 0;

// Global constants
const int8_t weights[9] = {17, 89, 39, 100, 70, 78, 11, 74, 52};
int weight_index = 0;

void print_stack_pointer() {
    uint32_t sp_val;
    asm volatile ("mv %0, sp" : "=r"(sp_val));
    printf("Initial SP: 0x%x\n", sp_val);
    uart_write_flush();
}

void dummy_delay() {
    volatile int d;
    for (d = 0; d < 500; d++) {
        asm volatile("nop");
    }
}

int main() {
    uart_init();
    print_stack_pointer();

    printf("Starting CNN accelerator test for all classes.\n");
    uart_write_flush();

    uint32_t t0, t1, t2;

    printf("Writing weights to CNN accelerator.\n");
    uart_write_flush();

    for (weight_index = 0; weight_index < 9; weight_index++) {
        uint32_t addr = CNN_BASE_ADDR + CNN_WEIGHT_BASE_REG + 4 * weight_index;
        int8_t weight = weights[weight_index];
    
        printf("Writing weight[%x] = %x to addr 0x%x\n", weight_index, weight, addr);
        uart_write_flush();
    
        *reg32(addr, 0) = weight;
    
        // Read back to verify
        volatile uint32_t confirm = *reg32(addr, 0);
        printf("Read back weight[%x]: 0x%x\n", weight_index, confirm);
        uart_write_flush();
    }


    *reg32(CNN_BASE_ADDR, CNN_INPUT_BASE_REG) = SRAM_BASE + IMAGE_OFFSET;

    asm volatile("csrr %0, mcycle" : "=r"(t0)::"memory");

    for (int class_idx = 0; class_idx < 10; class_idx++) {
        printf("Processing for class index: %x\n", class_idx);
        uart_write_flush();

        *reg32(CNN_BASE_ADDR, CNN_CLASS_IDX_REG) = class_idx;
        *reg32(CNN_BASE_ADDR, CNN_CTRL_REG) = 1;

        while (*reg32(CNN_BASE_ADDR, CNN_STATUS_REG) == 0);

        printf("Class %x: Completed processing.\n", class_idx);
        uart_write_flush();
    }

    asm volatile("csrr %0, mcycle" : "=r"(t1)::"memory");

    printf("Reading output results per class (from CNN internal scores):\n");
    uart_write_flush();

    for (int class_idx = 0; class_idx < 10; class_idx++) {
        uint32_t addr = CNN_BASE_ADDR + CNN_CLASS_SCORES_BASE + (class_idx * 4);
        uint32_t score = *reg32(addr, 0);

        printf("Class %x accumulated score: %x\n", class_idx, score);
        uart_write_flush();
    }

    asm volatile("csrr %0, mcycle" : "=r"(t2)::"memory");

    printf("Total execution cycles: CNN runs %x, Output reading %x\n", t1 - t0, t2 - t1);
    uart_write_flush();

    printf("CNN processing completed, writing return code.\n");
    uart_write_flush();

    return USER_FINISH_VALUE;
}
