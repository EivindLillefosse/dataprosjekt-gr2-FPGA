import re
import numpy as np
from pathlib import Path

# Paths
debug_path = Path('vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt')
coe_path = Path('model/fpga_weights_and_bias/layer_2_conv2d_1_weights.coe')

# Parse debug file to get LAYER1_POOL1_OUTPUT entries
pool1 = {}  # key (r,c) -> list of 8 ints
with debug_path.open('r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

for i,line in enumerate(lines):
    m = re.match(r'^LAYER1_POOL1_OUTPUT: \[(\d+),(\d+)\]', line)
    if m:
        r = int(m.group(1)); c = int(m.group(2))
        # next lines contain Filter_0..Filter_7
        vals = []
        for j in range(1,9):
            l = lines[i+j]
            mm = re.search(r'Filter_(\d+):\s*(-?\d+)', l)
            if mm:
                vals.append(int(mm.group(2)))
            else:
                vals.append(0)
        pool1[(r,c)] = vals

# Ensure we have region [0..2,0..2]
region = np.zeros((3,3,8), dtype=int)
for rr in range(3):
    for cc in range(3):
        key = (rr,cc)
        if key not in pool1:
            raise SystemExit(f'Pool1 entry {key} not found in debug file')
        region[rr,cc,:] = pool1[key]

print('Pool1 region (integers from debug, assumed Q1.6):')
for ch in range(8):
    print(f'channel {ch}:')
    print(region[:,:,ch])

# Parse COE file: extract hex stream
hexstream = ''
with coe_path.open('r') as f:
    text = f.read()
# find memory_initialization_vector= ... ;
m = re.search(r'memory_initialization_vector\s*=\s*(.*);', text, re.S)
if not m:
    raise SystemExit('COE memory_initialization_vector not found')
vec = m.group(1)
# remove commas, whitespace, and newlines
vec = re.sub(r'[^0-9A-Fa-f]', '', vec)
# ensure even length
if len(vec) % 2 != 0:
    raise SystemExit('Hex stream length odd')
bytes_list = [int(vec[i:i+2],16) for i in range(0,len(vec),2)]
# Each byte is one weight value in Q1.6 (signed 8-bit)
weights_signed = [b-256 if b>127 else b for b in bytes_list]
print('\nTotal weight bytes parsed:', len(weights_signed))

# Shape: addresses = 9(kernel positions)*8(channels) =72 addresses, each with 16 filters -> 72*16 =1152 bytes
if len(weights_signed) < 1152:
    print('Warning: parsed fewer than expected bytes, got', len(weights_signed))

# Build kernel for filter_idx=1
K = 3
C = 8
NUM_FILTERS = 16
filter_idx = 1
kernel_q = np.zeros((K,K,C), dtype=int)
for kr in range(K):
    for kc in range(K):
        for ch in range(C):
            addr = ((kr * K) + kc) * C + ch
            base = addr * NUM_FILTERS
            val = weights_signed[base + filter_idx]
            kernel_q[kr,kc,ch] = val

print('\nKernel (Q1.6 integers) for filter', filter_idx, ':')
for ch in range(C):
    print('ch', ch)
    print(kernel_q[:,:,ch])

# Compute per-element integer products: region * kernel_q
int_prods = np.zeros((K,K,C), dtype=int)
for kr in range(K):
    for kc in range(K):
        for ch in range(C):
            int_prods[kr,kc,ch] = int(region[kr,kc,ch]) * int(kernel_q[kr,kc,ch])

print('\nPer-element integer products:')
print(int_prods.reshape(-1))
A = int_prods.sum()
print('\nAccumulator A =', A)
shifted = A // 64
print('Shifted A//64 =', shifted)
# bias not included here (need bias COE) — but we can report shifted as pre-bias
print('Interpreted as float (Q1.6):', shifted/64.0)

# Done
