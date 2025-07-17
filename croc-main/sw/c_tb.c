#include "uart.h"
#include "print.h"
#include "gpio.h"
#include "util.h"
#include "config.h"

#define CNN_BASE_ADDR          0x20001000
#define CNN_CTRL_REG           0x00
#define CNN_STATUS_REG         0x04
#define CNN_INPUT_BASE_REG     0x08
#define CNN_WEIGHT_BASE_REG    0x10
#define CNN_CLASS_IDX_REG      0x14   // <-- New register for class index
#define CNN_CLASS_SCORES_BASE 0x20

#define SRAM_BASE              0x10000000
#define IMAGE_OFFSET           0x0900      // Matches InputImageBaseAddr

#define USER_FINISH_ADDR 0x03000008
#define USER_FINISH_VALUE 0xCAFEDEAD

volatile uint32_t status = 0;

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
    int8_t weights[9] = {17, 89, 39, 100, 70, 78, 11, 74, 52};

    // Write weights to CNN hardware registers
    printf("Writing weights to CNN accelerator.\n");
    for (int i = 0; i < 9; i++) {
        printf("Before weight write: i=%d weights[i]=%d\n", i, weights[i]);
        uart_write_flush();
    
        printf("About to write to addr=0x%08X\n", CNN_BASE_ADDR + CNN_WEIGHT_BASE_REG + 4*i);
        uart_write_flush();
    
        *reg32(CNN_BASE_ADDR, CNN_WEIGHT_BASE_REG + 4*i) = (int8_t)weights[i];
    
        // Optional: If you have GPIO debugging capability
        gpio_set(i);
    }



    *reg32(CNN_BASE_ADDR, CNN_INPUT_BASE_REG)  = SRAM_BASE + IMAGE_OFFSET;

    asm volatile("csrr %0, mcycle" : "=r"(t0)::"memory");

    for (int class_idx = 0; class_idx < 10; class_idx++) {
        printf("Processing for class index: %d\n", class_idx);
        uart_write_flush();
        *reg32(CNN_BASE_ADDR, CNN_CLASS_IDX_REG) = class_idx;

        *reg32(CNN_BASE_ADDR, CNN_CTRL_REG) = 1;

        //uint32_t timeout = 1000000;
        //while ((*reg32(CNN_BASE_ADDR, CNN_STATUS_REG) == 0) && --timeout);
        while (*reg32(CNN_BASE_ADDR, CNN_STATUS_REG) == 0);
        printf("Class %d: Completed processing.\n", class_idx);
        uart_write_flush();
        //if (timeout == 0) {
        //    printf("Error: CNN processing timeout for class index %d\n", class_idx);
        //} else {
        //    printf("Class %d: Completed processing.\n", class_idx);
        //}
    }

    asm volatile("csrr %0, mcycle" : "=r"(t1)::"memory");

    printf("Reading output results per class (from CNN internal scores):\n");
    for (int class_idx = 0; class_idx < 10; class_idx++) {
        uint32_t addr = CNN_BASE_ADDR + CNN_CLASS_SCORES_BASE + (class_idx * 4);
        uint32_t score = *reg32(addr, 0);
        printf("Class %d accumulated score: %u\n", class_idx, score);
        uart_write_flush();
    }

    asm volatile("csrr %0, mcycle" : "=r"(t2)::"memory");
    printf("Total execution cycles: CNN runs %u, Output reading %u\n", t1 - t0, t2 - t1);

    uart_write_flush();
    printf("CNN processing completed, writing return code.\n");
    //*reg32(USER_FINISH_ADDR, 0) = USER_FINISH_VALUE;
    //return 0;

    return USER_FINISH_VALUE;
}
