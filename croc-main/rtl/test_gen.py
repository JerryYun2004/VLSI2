import numpy as np
from tensorflow.keras.datasets import mnist

# Load MNIST test images
(_, _), (x_test, y_test) = mnist.load_data()

# Select an index (e.g., a '7' at index 13)
idx = 13
img = x_test[idx]  # shape (28, 28)
label = y_test[idx]
print(f"Selected digit: {label}")

# Flatten to 1D
pixels = img.flatten()  # length 784

# Generate SystemVerilog mem[...] assignments
base = 0x1A10_0000
for i, val in enumerate(pixels):
    print(f"mem[INPUT_BASE + {i}] = {val};")
