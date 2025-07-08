#include <stdint.h>

// -------------------------------
// CNN Register Map
// -------------------------------
#define CNN_BASE_ADDR        0x20001000U  // Replace with actual mapped base address
#define CNN_REG(offset)      (*(volatile uint32_t *)(CNN_BASE_ADDR + (offset)))

#define CNN_CTRL_OFFSET        0x00
#define CNN_STATUS_OFFSET      0x04
#define CNN_INPUT_BASE_OFFSET  0x08
#define CNN_OUTPUT_BASE_OFFSET 0x0C
#define CNN_WEIGHT_BASE_OFFSET 0x10  // weights[0] = 0x10, weights[1] = 0x14, ..., weights[8] = 0x30

// -------------------------------
// Helper Functions
// -------------------------------
void cnn_write_reg(uint32_t offset, uint32_t value) {
    CNN_REG(offset) = value;
}

uint32_t cnn_read_reg(uint32_t offset) {
    return CNN_REG(offset);
}

// Load 9 signed 8-bit weights into CNN register file
void cnn_load_weights(const int8_t weights[9]) {
    for (int i = 0; i < 9; ++i) {
        cnn_write_reg(CNN_WEIGHT_BASE_OFFSET + (i * 4), (uint32_t)(int32_t)weights[i]);
    }
}

// Set input/output buffer base addresses
void cnn_set_io_buffers(uint32_t input_base, uint32_t output_base) {
    cnn_write_reg(CNN_INPUT_BASE_OFFSET, input_base);
    cnn_write_reg(CNN_OUTPUT_BASE_OFFSET, output_base);
}

// Start CNN computation
void cnn_start() {
    cnn_write_reg(CNN_CTRL_OFFSET, 1);
}

// Wait until CNN signals completion
void cnn_wait_done() {
    while ((cnn_read_reg(CNN_STATUS_OFFSET) & 0x1) == 0);
}

// Read 8-bit result from memory-mapped output
uint8_t cnn_read_result(uint32_t output_addr) {
    return *(volatile uint8_t *)(output_addr);
}

// -------------------------------
// High-Level Test Function
// -------------------------------
void test_cnn_accelerator() {
    // Example weights and buffers
    int8_t weights[9] = {17, 89, 39, 100, 70, 78, 11, 74, 52};

    uint32_t input_base  = 0x1A100000;  // Make sure these match DEFAULT_INPUT_BASE
    uint32_t output_base = 0x1A100010;

    // Load weights
    cnn_load_weights(weights);

    // Set buffer addresses
    cnn_set_io_buffers(input_base, output_base);

    // Start accelerator
    cnn_start();

    // Wait for completion
    cnn_wait_done();

    // Read and print result
    uint8_t result = cnn_read_result(output_base);
    // Replace this with platform-specific print if needed
    volatile uint8_t debug = result;  // Breakpoint/watch this if no stdout
}
