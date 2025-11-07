#!/usr/bin/env python3
import numpy as np

# load parsed COE filter0 (msb-first interpretation likely correct)
d = np.load('model/conv2_filter0_coe_parsed.npz')
f0_lsb = d['lsb']  # shape 3x3x8 (LSB-first interpretation)
f0_lsb_int = f0_lsb.astype(int)

# load bias COE
with open('model/fpga_weights_and_bias/layer_2_conv2d_1_biases.coe','r') as f:
    text = f.read()
vec = text.split('memory_initialization_vector=')[-1].split(';')[0]
parts = [p.strip() for p in vec.split(',') if p.strip()]
# parse hex bytes
bias_int8 = [int(p,16) - 256 if int(p,16) & 0x80 else int(p,16) for p in parts]
# filter 0 bias
b0 = bias_int8[0]

# Pool1 window raw ints from VHDL (Q9.6). These were printed earlier by extract script.
# Prefer Pool1 values from the Python NPZ (layer_1_output). If present, use the
# 3x3 window at (0,0). Convert Python floats (Q real) to Q9.6 raw ints so the
# manual calculation matches the VHDL integer representation. If the NPZ is
# missing, fall back to the previously hardcoded VHDL-extracted raw ints.
try:
    npz = np.load('model/intermediate_values.npz')
    if 'layer_1_output' in npz:
        pool1_py = npz['layer_1_output']  # shape (13,13,8)
        # take 3x3 window at (0,0)
        pool_window = pool1_py[0:3, 0:3, :]
        # convert to Q9.6 raw ints by multiplying by 64 and rounding to nearest int
        pool1_raw = np.rint(pool_window * 64.0).astype(int)
        pool = pool1_raw.reshape(3,3,8)
        print('Loaded Pool1 from NPZ (layer_1_output) and converted to Q9.6 ints')
    else:
        raise KeyError('layer_1_output not in NPZ')
except Exception as e:
    print('Failed to load Pool1 from NPZ, using hardcoded VHDL-extracted raw ints. Err:', e)
    pool1_raw = np.array([
        [0, 11, 0, 0, 103, 0, 0, 0],
        [0, 17, 0, 0, 161, 0, 0, 0],
        [0, 23, 0, 0, 219, 0, 0, 0],
        [0, 17, 0, 0, 161, 0, 0, 0],
        [0, 23, 0, 0, 219, 0, 0, 0],
        [0, 29, 0, 0, 277, 0, 0, 0],
        [0, 23, 0, 0, 219, 0, 0, 0],
        [0, 29, 0, 0, 277, 0, 0, 0],
        [0, 35, 0, 0, 335, 0, 0, 0]
    ])
    pool = pool1_raw.reshape(3,3,8)

# convert pool Q9.6 raw ints to floats: divide by 64
pool_float = pool.astype(float) / 64.0

# Print detailed pool info for cross-checking with VHDL
print('\n--- Pool1 (Q9.6 raw ints) 3x3x8 window ---')
print(pool)
print('\n--- Pool1 floats (pool / 64) ---')
with np.printoptions(precision=6, suppress=True):
    print(pool_float)

# convert weights Q1.6 signed int8 to floats: divide by 64
weights_float = f0_lsb_int.astype(float) / 64.0

# Print detailed weight info for cross-checking with VHDL
print('\n--- Weights (LSB-first) int8 3x3x8 ---')
print(f0_lsb_int)
print('\n--- Weights floats (Q1.6) ---')
with np.printoptions(precision=6, suppress=True):
    print(weights_float)

# compute MAC: sum(pool * weight)
mac = 0.0
print('\n--- Per-element products and running MAC sum ---')
for kr in range(3):
    for kc in range(3):
        for ch in range(8):
            p = pool_float[kr,kc,ch]
            w = weights_float[kr,kc,ch]
            prod = p * w
            mac += prod
            # raw integer representations
            p_int = int(pool[kr,kc,ch])
            w_int = int(f0_lsb_int[kr,kc,ch])
            prod_num = p_int * w_int  # integer numerator; actual prod = prod_num / 4096
            # running MAC numerator (sum of prod_num)
            if 'mac_num' not in globals():
                mac_num = 0
            mac_num += prod_num
            # print both float and raw integer numerator forms
            print(f'[{kr},{kc},{ch}] pool_int={p_int:4d} weight_int={w_int:4d} prod_num={prod_num:6d} ' +
                  f'prod={prod:0.8f} running_mac={mac:0.8f} running_mac_num={mac_num:8d}')

# add bias: bias in Q1.6 -> float = b0 / 64
bias_float = b0 / 64.0
out = mac + bias_float
relu = max(0.0, out)
print('Manual MAC sum:', mac)
print('Bias (int8):', b0, 'Bias float:', bias_float)
print('Output before ReLU:', out)
print('Output after ReLU:', relu)

# Compare to Python NPZ reference if available
npz = np.load('model/intermediate_values.npz')
py_conv2_0 = npz['layer_2_filter_0']
print('Python reference layer_2_filter_0[0,0]:', py_conv2_0[0,0])

# VHDL value from debug log observed earlier: raw 720 -> float 720/64
print('VHDL reported Conv2[0,0] Filter0 raw (from debug): 720 ->', 720/64.0)
