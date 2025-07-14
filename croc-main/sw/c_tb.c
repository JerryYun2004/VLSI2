#include "uart.h"
#include "print.h"
#include "gpio.h"
#include "util.h"
#include "config.h"

#define CNN_BASE_ADDR          0x1A104000
#define CNN_CTRL_REG           0x00
#define CNN_STATUS_REG         0x04
#define CNN_INPUT_BASE_REG     0x08
#define CNN_OUTPUT_BASE_REG    0x0C
#define CNN_WEIGHT_BASE_REG    0x10
#define CNN_CLASS_IDX_REG      0x14   // <-- New register for class index
#define CNN_CLASS_SCORES_BASE 0x20

#define SRAM_BASE              0x10000000
#define IMAGE_OFFSET           0x1000      // Matches InputImageBaseAddr
#define OUTPUT_OFFSET          0x2000      // Distinct region to store outputs for all classes

void* memcpy(void* dest, const void* src, unsigned int n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    while (n--) {
        *d++ = *s++;
    }
    return dest;
}

int main() {
    uart_init();
    printf("Starting CNN accelerator test for all classes.\n");
    uart_write_flush();

    uint32_t t0, t1, t2;
    uint8_t weights[9] = {17, 89, 39, 100, 70, 78, 11, 74, 52};

    // Write weights to CNN hardware registers
    printf("Writing weights to CNN accelerator.\n");
    for (int i = 0; i < 9; i++) {
        *reg32(CNN_BASE_ADDR, CNN_WEIGHT_BASE_REG + 4*i) = (int8_t)weights[i];
    }

    *reg32(CNN_BASE_ADDR, CNN_INPUT_BASE_REG)  = SRAM_BASE + IMAGE_OFFSET;
    *reg32(CNN_BASE_ADDR, CNN_OUTPUT_BASE_REG) = SRAM_BASE + OUTPUT_OFFSET;

    asm volatile("csrr %0, mcycle" : "=r"(t0)::"memory");

    for (int class_idx = 0; class_idx < 10; class_idx++) {
        printf("Processing for class index: %d\n", class_idx);
        *reg32(CNN_BASE_ADDR, CNN_CLASS_IDX_REG) = class_idx;

        *reg32(CNN_BASE_ADDR, CNN_CTRL_REG) = 1;

        while (*reg32(CNN_BASE_ADDR, CNN_STATUS_REG) == 0);

        printf("Class %d: Completed processing.\n", class_idx);
    }

    asm volatile("csrr %0, mcycle" : "=r"(t1)::"memory");

    printf("Reading output results per class (from CNN internal scores):\n");
    for (int class_idx = 0; class_idx < 10; class_idx++) {
        uint32_t addr = CNN_BASE_ADDR + CNN_CLASS_SCORES_BASE + (class_idx * 4);
        uint32_t score = *reg32(addr, 0);
        printf("Class %d accumulated score: %u\n", class_idx, score);
    }

    asm volatile("csrr %0, mcycle" : "=r"(t2)::"memory");
    printf("Total execution cycles: CNN runs %u, Output reading %u\n", t1 - t0, t2 - t1);

    uart_write_flush();
    return 0;
}
