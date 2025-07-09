#include <stdint.h>

#define CNN_BASE         0x1A104000
#define CNN_CTRL         (CNN_BASE + 0x00)
#define CNN_STATUS       (CNN_BASE + 0x04)
#define CNN_INPUT_BASE   (CNN_BASE + 0x08)
#define CNN_OUTPUT_BASE  (CNN_BASE + 0x0C)
#define CNN_WEIGHT_BASE  (CNN_BASE + 0x10)

#define SRAM_BASE        0x1C000000
#define IMAGE_OFFSET     0x000       // Location of input image in SRAM
#define OUTPUT_OFFSET    0x400       // Location of output buffer in SRAM

int main() {
    // Write CNN weights
    uint8_t weights[9] = {17, 89, 39, 100, 70, 78, 11, 74, 52};
    for (int i = 0; i < 9; i++) {
        *((volatile uint32_t*)(CNN_WEIGHT_BASE + 4*i)) = (int8_t)weights[i];
    }

    // Set input/output memory locations
    *((volatile uint32_t*)CNN_INPUT_BASE)  = SRAM_BASE + IMAGE_OFFSET;
    *((volatile uint32_t*)CNN_OUTPUT_BASE) = SRAM_BASE + OUTPUT_OFFSET;

    // Start the CNN accelerator
    *((volatile uint32_t*)CNN_CTRL) = 1;

    // Wait for CNN to finish
    while (*((volatile uint32_t*)CNN_STATUS) == 0);

    // Read CNN output probabilities (assuming softmax over 10 digits)
    int max_index = 0;
    int max_value = -1;

    for (int i = 0; i < 10; i++) {
        int val = *((volatile uint8_t*)(SRAM_BASE + OUTPUT_OFFSET + i));
        if (val > max_value) {
            max_value = val;
            max_index = i;
        }
    }

    // Set return code with prediction in lower nibble
    *((volatile uint32_t*)0x1A106000) = 0xDEADB000 | (max_index & 0xF);

    return 0;
}

// Minimal implementation of memcpy for freestanding environments
void* memcpy(void* dest, const void* src, unsigned int n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    while (n--) {
        *d++ = *s++;
    }
    return dest;
}
