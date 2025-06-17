import numpy as np
from tensorflow.keras.datasets import mnist

# Load MNIST data
(_, _), (x_test, y_test) = mnist.load_data()

MAX_TESTS = 100
images = x_test[:MAX_TESTS].reshape(MAX_TESTS, -1)  # shape (100, 784)
labels = y_test[:MAX_TESTS]                         # shape (100,)

# Save 78400 pixel values into input_image.mem
with open("input_image.mem", "w") as f:
    for image in images:
        for px in image:
            f.write(f"{px:02x}\n")  # hex format, 2-digit

# Save 100 labels into labels.mem
with open("labels.mem", "w") as f:
    for label in labels:
        f.write(f"{label:01x}\n")  # hex format, 1-digit
