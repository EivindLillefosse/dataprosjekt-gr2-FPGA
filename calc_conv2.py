import numpy as np

def hex_to_signed_q1_6(hex_str):
    '''Convert 2-char hex to signed Q1.6 float'''
    val = int(hex_str, 16)
    if val >= 128:
        val -= 256
    return val / 64.0

# Read COE file
with open('model/fpga_weights_and_bias/layer_2_conv2d_1_weights.coe', 'r') as f:
    content = f.read()

# Find the vector data
vector_start = content.find('memory_initialization_vector=')
if vector_start == -1:
    raise ValueError("Could not find memory_initialization_vector")

vector_data = content[vector_start + len('memory_initialization_vector='):]
# Remove whitespace, newlines, and trailing semicolon
vector_data = vector_data.replace('\n', '').replace(' ', '').rstrip(';')

# Split by comma
hex_data = [h.strip() for h in vector_data.split(',') if h.strip()]

print(f'Total addresses: {len(hex_data)}')
print(f'Expected: 3*3*8 = 72 addresses')

# Check if we're missing some
if len(hex_data) < 72:
    print(f'WARNING: Only found {len(hex_data)} addresses, padding with zeros')
    while len(hex_data) < 72:
        hex_data.append('00' * 16)  # Add zero weights

# Parse weights: Shape (3, 3, 8, 16) = kernel_row, kernel_col, input_channel, output_filter
# Each address contains 16 filters (32 hex chars = 16 bytes)
# MSB-first: Filter 0 at chars [0:2], Filter 1 at [2:4], ..., Filter 15 at [30:32]

weights = np.zeros((3, 3, 8, 16))

addr_idx = 0
for kr in range(3):
    for kc in range(3):
        for ch in range(8):
            hex_line = hex_data[addr_idx]
            # Extract all 16 filters from this address
            for filt in range(16):
                hex_byte = hex_line[filt*2:(filt*2)+2]
                weights[kr, kc, ch, filt] = hex_to_signed_q1_6(hex_byte)
            addr_idx += 1

print(f'\nWeights shape: {weights.shape}')

# Use VHDL Pool1 outputs (Q1.6 quantized values from debug file)
# These are the ACTUAL values the VHDL Conv2 sees!
pool1_vhdl_raw = np.array([
    # [0,0]  [0,1]  [0,2]
    [[0, 11, 0, 0, 103, 0, 0, 0],  # [0,0]
     [0, 17, 0, 0, 127, 0, 0, 0],  # [0,1]
     [0, 23, 0, 0, 127, 0, 0, 0]], # [0,2]
    # [1,0]  [1,1]  [1,2]
    [[0, 17, 0, 0, 127, 0, 0, 0],  # [1,0]
     [0, 23, 0, 0, 127, 0, 0, 0],  # [1,1]
     [0, 29, 0, 0, 127, 0, 0, 0]], # [1,2]
    # [2,0]  [2,1]  [2,2]
    [[0, 23, 0, 0, 127, 0, 0, 0],  # [2,0]
     [0, 29, 0, 0, 127, 0, 0, 0],  # [2,1]
     [0, 35, 0, 0, 127, 0, 0, 0]], # [2,2]
])

# Convert to Q1.6 float values
pool1 = pool1_vhdl_raw.astype(np.float32) / 64.0

print(f'Pool1 shape: {pool1.shape}')
print(f'Pool1 VHDL values (Q1.6 quantized):')
print(pool1)

# Calculate Conv2 [0,0], Filter 0
print('\n=== MANUAL CONVOLUTION: Conv2 [0,0], Filter 0 ===\n')

filter_idx = 0
accumulator = 0.0

print('Kernel | Input  | Ch | Pixel     | Weight   | Product   | Accumulator')
print('='*80)

for kr in range(3):
    for kc in range(3):
        # Pool1 input position for this kernel element
        pr = 0 + kr  # Output position [0,0] + kernel offset
        pc = 0 + kc
        
        for ch in range(8):
            # Get pixel value (with padding if out of bounds)
            if pr < pool1.shape[0] and pc < pool1.shape[1]:
                pixel = pool1[pr, pc, ch]
            else:
                pixel = 0.0  # Zero padding
            
            weight = weights[kr, kc, ch, filter_idx]
            product = pixel * weight
            accumulator += product
            
            # Only show non-zero contributions
            if abs(pixel) > 0.001 or abs(weight) > 0.001:
                print(f' [{kr},{kc}] | [{pr},{pc}] | {ch} | {pixel:9.5f} | {weight:8.4f} | {product:9.5f} | {accumulator:9.5f}')

# Load bias
with open('model/fpga_weights_and_bias/layer_2_conv2d_1_biases.coe', 'r') as f:
    bias_content = f.read()

# Find vector data
bias_vector_start = bias_content.find('memory_initialization_vector=')
if bias_vector_start == -1:
    raise ValueError("Could not find bias vector")

bias_vector_data = bias_content[bias_vector_start + len('memory_initialization_vector='):]
bias_vector_data = bias_vector_data.replace('\n', '').replace(' ', '').rstrip(';')
bias_data = [h.strip() for h in bias_vector_data.split(',') if h.strip()]

biases = np.array([hex_to_signed_q1_6(b) for b in bias_data])
bias_f0 = biases[filter_idx]

print(f'\n{"="*80}')
print(f'Accumulator before bias: {accumulator:9.5f}')
print(f'Bias for filter 0:       {bias_f0:9.5f}')
result_after_bias = accumulator + bias_f0
print(f'Result after bias:       {result_after_bias:9.5f}')

# ReLU
result_after_relu = max(0.0, result_after_bias)
print(f'Result after ReLU:       {result_after_relu:9.5f}')

# Compare with Python
data = np.load('model/intermediate_values.npz')
conv2_output = data['layer_2_output']
expected = conv2_output[0, 0, filter_idx]
print(f'\nExpected (Python):       {expected:9.5f}')
print(f'Calculated (Manual):     {result_after_relu:9.5f}')
print(f'Difference:              {abs(expected - result_after_relu):9.5f}')

# Q1.6 representation
q1_6_raw = round(result_after_relu * 64)
q1_6_saturated = min(127, max(-128, q1_6_raw))
q1_6_value = q1_6_saturated / 64.0

print(f'\n--- Q1.6 Quantization ---')
print(f'Raw value:               {result_after_relu:9.5f}')
print(f'Q1.6 scaled (×64):       {result_after_relu * 64:9.2f}')
print(f'Q1.6 raw integer:        {q1_6_raw}')
print(f'Q1.6 saturated:          {q1_6_saturated} (max=127, min=-128)')
print(f'Q1.6 final value:        {q1_6_value:9.5f}')
print(f'Q1.6 max possible:       1.984375 (127/64)')
print(f'\nSaturation occurred:     {"YES - OUTPUT CLIPPED!" if q1_6_raw > 127 else "NO"}')
