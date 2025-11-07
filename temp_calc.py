import numpy as np

# Conv2 weights: (3, 3, 8, 16) = kernel_row, kernel_col, input_channel, output_filter
# Memory packing: Each address stores all 16 filters for one (kernel_row, kernel_col, input_channel)
# MSB-first: Filter 0 is bits [127:120], Filter 1 is [119:112], ..., Filter 15 is [7:0]
# So in hex string (32 chars = 16 bytes), Filter 0 is chars [0:2], Filter 1 is [2:4], etc.

# Reorganize weight data by kernel position and channel
weight_data = {}
for kernel_row in range(3):
    for kernel_col in range(3):
        for input_ch in range(8):
            # Calculate which line this is: row*3*8 + col*8 + ch
            line_idx = kernel_row * 3 * 8 + kernel_col * 8 + input_ch
            # But we only have 9 lines in weight_lines...
            # Wait, let me re-read the structure

# Actually looking at the data: we have addresses for each (kernel_pos, channel) combo
# That's 3*3=9 kernel positions, each with some channels
# Let's just parse what we have

weight_lines = [
    'FB0103FA07FB0107FD030008F8F90202',  # kernel [0,0], channels 0-7
    '0501FA03F705060405FD0700FD07F6F7',  # kernel [0,1], channels 0-7
    'FDF50601FFF801030305FB00FD0AF902',  # kernel [0,2], channels 0-7
    '0602F707F7FBFAFBFFF70409F8FD0308',  # kernel [1,0], channels 0-7
    'F505FBFAF6F9F8FFFC06FBFD0501FD05',  # kernel [1,1], channels 0-7
    'FCF8FBF70408F8FBF4FC0CFD04FE08F7',  # kernel [1,2], channels 0-7
    '000406F8FAFDF80807FE04FE04FFF602',  # kernel [2,0], channels 0-7
    '0602F8FF0109FC0304080606FC030006',  # kernel [2,1], channels 0-7
    '04F9F7FDFB07FB02F808F60906FC0202',  # kernel [2,2], channels 0-7
]

def hex_to_signed_q1_6(hex_str):
    '''Convert 2-char hex to signed Q1.6 float'''
    val = int(hex_str, 16)
    if val >= 128:
        val -= 256
    return val / 64.0

# Extract filter 0 weights (leftmost byte = MSB)
print('Filter 0 weights (Q1.6):')
print('Kernel pos | Ch0    Ch1    Ch2    Ch3    Ch4    Ch5    Ch6    Ch7')
print('='*70)

filter0_weights = []
for idx, line in enumerate(weight_lines):
    row = idx // 3
    col = idx % 3
    weights_for_channels = []
    # Extract all 16 filters, but we only care about filter 0 (MSB)
    for ch in range(8):
        # Each filter is 1 byte (8 bits), 2 hex chars
        # MSB-first packing: Filter 0 is leftmost byte
        # Filter 0 is always at position 0-1 (first 2 hex chars)
        hex_byte = line[0:2]
        weight = hex_to_signed_q1_6(hex_byte)
        weights_for_channels.append(weight)
        # Move to next channel (skip all 16 filters = 32 hex chars)
        if ch < 7:
            line = line[2:]  # Remove processed filter 0 byte
    
    filter0_weights.append(weights_for_channels)
    print(f'  [{row},{col}]   | {" ".join(f"{w:6.3f}" for w in weights_for_channels)}')

print('\n\nFilter 0 weights as 3x3x8 array:')
weights_3d = np.array(filter0_weights).reshape(3, 3, 8)
print(weights_3d)

# Load Pool1 outputs
data = np.load('model/intermediate_values.npz')
pool1 = data['layer_1_output']

print('\n\nPool1 outputs for Conv2 [0,0] receptive field:')
print('Position | Ch0    Ch1    Ch2    Ch3    Ch4    Ch5    Ch6    Ch7')
print('='*70)
for r in range(3):
    for c in range(3):
        if r < pool1.shape[0] and c < pool1.shape[1]:
            vals = pool1[r, c, :]
            print(f'  [{r},{c}]  | {" ".join(f"{v:6.3f}" for v in vals)}')
        else:
            # Padding with zeros
            print(f'  [{r},{c}]  |  0.000  0.000  0.000  0.000  0.000  0.000  0.000  0.000 (padding)')

# Manual convolution calculation
print('\n\n=== MANUAL CONVOLUTION CALCULATION ===')
print('Conv2 output [0,0], Filter 0:\n')

accumulator = 0.0
for kr in range(3):
    for kc in range(3):
        pr = kr  # Pool1 position row
        pc = kc  # Pool1 position col
        
        print(f'Kernel [{kr},{kc}]:')
        
        for ch in range(8):
            if pr < pool1.shape[0] and pc < pool1.shape[1]:
                pixel = pool1[pr, pc, ch]
            else:
                pixel = 0.0  # Padding
            
            weight = weights_3d[kr, kc, ch]
            product = pixel * weight
            accumulator += product
            
            if pixel != 0.0 or weight != 0.0:  # Only print non-zero contributions
                print(f'  Ch{ch}: {pixel:8.5f} × {weight:7.4f} = {product:9.5f} → acc = {accumulator:9.5f}')

# Get bias for filter 0
bias_line = 'FE,00,01,00,00,05,00,FF,FF,00,FE,FD,FF,FF,FE,FE'
biases = [hex_to_signed_q1_6(b.strip()) for b in bias_line.split(',')]
bias_f0 = biases[0]

print(f'\n\nAccumulator before bias: {accumulator:.5f}')
print(f'Bias for filter 0: {bias_f0:.5f}')
result_after_bias = accumulator + bias_f0
print(f'Result after bias: {result_after_bias:.5f}')

# ReLU
result_after_relu = max(0.0, result_after_bias)
print(f'Result after ReLU: {result_after_relu:.5f}')

# Get expected Python output
conv2_output = data['layer_2_output']
expected = conv2_output[0, 0, 0]
print(f'\nExpected (Python): {expected:.5f}')
print(f'Calculated: {result_after_relu:.5f}')
print(f'Difference: {abs(expected - result_after_relu):.5f}')

# Q1.6 quantization (what VHDL would produce if not saturating)
q1_6_value = round(result_after_relu * 64) / 64
print(f'\nQ1.6 quantized: {q1_6_value:.5f} (raw: {round(result_after_relu * 64)})')
print(f'Q1.6 saturated at max: 127/64 = 1.984375')
