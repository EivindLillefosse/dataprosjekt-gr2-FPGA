#!/usr/bin/env python3
"""
Extract Pool1 outputs from VHDL debug log and manually calculate Conv2 [0,0] Filter 0
"""
import re
import numpy as np
import os

# Detect if we're in model/ or root directory
if os.path.exists('model/fpga_weights_and_bias'):
    # Running from root
    debug_file = 'vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt'
    npz_file = 'model/intermediate_values.npz'
    weights_file = 'model/fpga_weights_and_bias/layer_2_conv2d_1_weights.coe'
    biases_file = 'model/fpga_weights_and_bias/layer_2_conv2d_1_biases.coe'
elif os.path.exists('fpga_weights_and_bias'):
    # Running from model/
    debug_file = '../vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt'
    npz_file = 'intermediate_values.npz'
    weights_file = 'fpga_weights_and_bias/layer_2_conv2d_1_weights.coe'
    biases_file = 'fpga_weights_and_bias/layer_2_conv2d_1_biases.coe'
else:
    raise FileNotFoundError("Cannot find fpga_weights_and_bias directory")

# Read the debug file
with open(debug_file, 'r') as f:
    lines = f.readlines()

# Parse Pool1 outputs
pool1_data = {}
i = 0
while i < len(lines):
    line = lines[i].strip()
    m = re.match(r'LAYER1_POOL1_OUTPUT: \[(\d+),(\d+)\]', line)
    if m:
        r, c = int(m.group(1)), int(m.group(2))
        filters = []
        i += 1
        while i < len(lines) and lines[i].strip().startswith('Filter_'):
            fm = re.match(r'Filter_(\d+):\s*(-?\d+)', lines[i].strip())
            if fm:
                filters.append(int(fm.group(2)))
            i += 1
        if (r, c) not in pool1_data:
            pool1_data[(r, c)] = filters
    else:
        i += 1

# Print the 3x3 window for Conv2 [0,0]
print('=' * 80)
print('Pool1 values for Conv2 [0,0] calculation (3x3 window, 8 channels)')
print('=' * 80)
print('Format: [row, col] -> raw values (16-bit signed)')
print()

# Build the 3x3x8 input tensor for Conv2 [0,0]
pool1_window = np.zeros((3, 3, 8))
for row in range(3):
    for col in range(3):
        key = (row, col)
        if key in pool1_data:
            vals = pool1_data[key]
            # Convert to Q9.6 floats (scale=64)
            floats = [v/64.0 for v in vals]
            pool1_window[row, col, :] = floats
            print(f'Pool1[{row},{col}]: raw={vals}')
            print(f'              Q9.6={[f"{v:.5f}" for v in floats]}')
        else:
            print(f'Pool1[{row},{col}]: NOT FOUND')
print()

# Now load Conv2 weights for filter 0
# We need the layer2_conv2d_1_weights for all 8 input channels, filter 0
# The weights are in model/fpga_weights_and_bias/
print('=' * 80)
print('Loading Conv2 Layer weights and bias from NPZ')
print('=' * 80)

# Load intermediate values (includes weights if exported)
try:
    data = np.load(npz_file)
    print(f"Available keys: {list(data.keys())}")
    
    # Try to load Conv2 filter 0 weights directly if available
    # Otherwise, we'll load from the COE or use the model weights
    
except FileNotFoundError:
    print("intermediate_values.npz not found. Cannot load weights for comparison.")
    print("Run: python model/CNN.py first")
    exit(1)

# Load weights directly from the intermediate NPZ or COE files
print()
print('=' * 80)
print('Manual Conv2 [0,0] Filter 0 Calculation')
print('=' * 80)
print('Using Pool1 VHDL outputs and Conv2 Filter 0 from Python NPZ')
print()

# The NPZ has per-filter intermediate activations; we need to load weights separately
# Let's parse the COE file for layer2_conv2d_1_weights
def parse_coe_weights(filename):
    """Parse a COE file and return weights as a list of integers."""
    with open(filename, 'r') as f:
        content = f.read()
    
    # Find the memory_initialization_vector using regex to handle multi-line
    match = re.search(r'memory_initialization_vector=([^;]+);', content, re.DOTALL)
    if match:
        hex_str = match.group(1)
        # Split by comma and strip whitespace
        hex_vals = [h.strip() for h in hex_str.split(',') if h.strip()]
        # Each hex value is 128 bits = 32 hex chars = 16 bytes (16 filters packed)
        weights = []
        for h in hex_vals:
            if len(h) == 32:  # 128-bit value
                # Parse each pair of hex chars as one byte (MSB first)
                for i in range(0, 32, 2):
                    byte_hex = h[i:i+2]
                    val = int(byte_hex, 16)
                    if val >= 128:
                        val -= 256  # Two's complement for 8-bit
                    weights.append(val)
        return weights
    return []
    return []

# Load Conv2 weights
weights_coe = parse_coe_weights(weights_file)
print(f"Loaded {len(weights_coe)} weight values from COE file")

# Conv2 shape: (3, 3, 8 input channels, 16 filters)
# Total weights = 3*3*8*16 = 1152
# Each BRAM address holds weights for ALL 16 filters at one (kr,kc,ch) position
# MSB-first packing: address_data[127:120] = filter 0, address_data[7:0] = filter 15

# Reconstruct filter 0 weights (3x3x8)
filter0_weights_q = np.zeros((3, 3, 8), dtype=np.int32)

# The COE packing for Conv2: 16 filters per address
# Address = ((kr * 3) + kc) * 8 + ch
# Each address stores 16 bytes (one per filter)
# Filter 0 is the FIRST byte at each address (MSB-first)

for kr in range(3):
    for kc in range(3):
        for ch in range(8):
            addr = ((kr * 3) + kc) * 8 + ch
            # Each COE entry is packed 16 bytes; filter 0 is first
            filter0_weights_q[kr, kc, ch] = weights_coe[addr * 16]  # First filter

print("Filter 0 weights (Q1.6 format from COE):")
for ch in range(8):
    print(f"  Channel {ch}:")
    for kr in range(3):
        row_vals = [filter0_weights_q[kr, kc, ch] for kc in range(3)]
        row_floats = [v/64.0 for v in row_vals]
        print(f"    Row {kr}: {row_vals} -> {[f'{v:.5f}' for v in row_floats]}")
print()

# Load bias for filter 0
def parse_coe_biases(filename):
    """Parse bias COE and return list."""
    with open(filename, 'r') as f:
        lines = f.readlines()
    for line in lines:
        if line.strip().startswith('memory_initialization_vector='):
            hex_str = line.strip().split('=')[1].rstrip(';')
            hex_vals = [h.strip() for h in hex_str.split(',')]
            biases = []
            for h in hex_vals:
                val = int(h, 16)
                if val >= 128:
                    val -= 256
                biases.append(val)
            return biases
    return []

biases_coe = parse_coe_biases(biases_file)
bias_filter0_q = biases_coe[0]
bias_filter0 = bias_filter0_q / 64.0
print(f"Filter 0 bias (Q1.6): {bias_filter0_q} -> {bias_filter0:.5f}")
print()

# Perform the convolution manually
accumulator = 0
print("MAC operations (Pool1_value * Weight):")
mac_count = 0
for kr in range(3):
    for kc in range(3):
        for ch in range(8):
            pool_val = pool1_window[kr, kc, ch]
            weight_val = filter0_weights_q[kr, kc, ch] / 64.0
            product = pool_val * weight_val
            accumulator += product
            if pool_val != 0 or weight_val != 0:  # Only print non-zero contributions
                print(f"  [{kr},{kc}][ch{ch}]: {pool_val:.5f} * {weight_val:.5f} = {product:.5f}")
            mac_count += 1

print()
print(f"Total MAC operations: {mac_count}")
print(f"Accumulator (before bias): {accumulator:.5f}")

# Add bias
result_with_bias = accumulator + bias_filter0
print(f"Bias (Filter 0): {bias_filter0:.5f}")
print(f"Result (after bias): {result_with_bias:.5f}")

# Apply ReLU
result_relu = max(0.0, result_with_bias)
print(f"Result (after ReLU): {result_relu:.5f}")
print()

# Compare to Python expected
python_expected = data['layer_2_output'][0, 0, 0]  # Conv2 [0,0] Filter 0
print(f"Python expected (layer_2_output[0,0,0]): {python_expected:.5f}")
print(f"Manual calculation result: {result_relu:.5f}")
print(f"Difference: {abs(python_expected - result_relu):.5f}")

# Also check VHDL Conv2 output
print()
print("Checking VHDL Conv2 output...")
# Parse Conv2 output from debug log
i = 0
while i < len(lines):
    line = lines[i].strip()
    m2 = re.match(r'LAYER2_CONV2_OUTPUT: \[0,0\]', line)
    if m2:
        i += 1
        while i < len(lines) and lines[i].strip().startswith('Filter_'):
            fm2 = re.match(r'Filter_0:\s*(-?\d+)', lines[i].strip())
            if fm2:
                vhdl_raw = int(fm2.group(1))
                vhdl_float = vhdl_raw / 64.0
                print(f"VHDL Conv2[0,0] Filter 0: raw={vhdl_raw} -> Q9.6={vhdl_float:.5f}")
                print(f"VHDL vs Manual calc: {abs(vhdl_float - result_relu):.5f}")
                print(f"VHDL vs Python: {abs(vhdl_float - python_expected):.5f}")
                break
            i += 1
        break
    i += 1

print()
print('=' * 80)
