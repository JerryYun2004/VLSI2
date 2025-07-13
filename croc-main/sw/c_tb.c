// Copyright (c) 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// Yun Zizhuo

#include "uart.h"
#include "print.h"
#include "gpio.h"
#include "util.h"
#include "config.h"

#define TB_FREQUENCY 10000000
#define TB_BAUDRATE    115200

#define CNN_BASE_ADDR      0x1A104000
#define CNN_CTRL_REG       0x00
#define CNN_STATUS_REG     0x04
#define CNN_INPUT_BASE_REG 0x08
#define CNN_OUTPUT_BASE_REG 0x0C
#define CNN_WEIGHT_BASE_REG 0x10

#define SRAM_BASE        0x1C000000
#define IMAGE_OFFSET     0x000       // Input image location
#define OUTPUT_OFFSET    0x400       // Output buffer location

int main() {
    uart_init();
    printf("Starting CNN accelerator test.\n");
    uart_write_flush();

    uint32_t t0, t1, t2, t3;

    uint8_t weights[9] = {17, 89, 39, 100, 70, 78, 11, 74, 52};

    // Write weights to CNN hardware registers
    printf("Writing weights to CNN accelerator.\n");
    for (int i = 0; i < 9; i++) {
        *reg32(CNN_BASE_ADDR, CNN_WEIGHT_BASE_REG + 4*i) = (int8_t)weights[i];
    }

    // Set memory locations for input and output
    *reg32(CNN_BASE_ADDR, CNN_INPUT_BASE_REG)  = SRAM_BASE + IMAGE_OFFSET;
    *reg32(CNN_BASE_ADDR, CNN_OUTPUT_BASE_REG) = SRAM_BASE + OUTPUT_OFFSET;

    // Record start time
    asm volatile("csrr %0, mcycle" : "=r"(t0)::"memory");

    // Start the CNN accelerator
    *reg32(CNN_BASE_ADDR, CNN_CTRL_REG) = 1;

    // Wait for CNN to finish
    while (*reg32(CNN_BASE_ADDR, CNN_STATUS_REG) == 0);

    asm volatile("csrr %0, mcycle" : "=r"(t1)::"memory");

    printf("CNN computation finished. Reading outputs...\n");

    int max_index = 0;
    int max_value = -1;

    for (int i = 0; i < 10; i++) {
        int val = *((volatile uint8_t*)(SRAM_BASE + OUTPUT_OFFSET + i));
        printf("Class %d: %d\n", i, val);
        if (val > max_value) {
            max_value = val;
            max_index = i;
        }
    }

    asm volatile("csrr %0, mcycle" : "=r"(t2)::"memory");

    printf("CNN prediction: %d with confidence %d.\n", max_index, max_value);
    printf("Execution cycles: CNN compute %u, Output processing %u\n", t1 - t0, t2 - t1);

    // Set return code in designated memory (user-defined)
    *reg32(0x1A106000, 0x0) = 0xDEADB000 | (max_index & 0xF);

    uart_write_flush();
    return 0;
}
