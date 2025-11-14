#!/usr/bin/env python3
from pathlib import Path
import re
import numpy as np
REPO = Path(r"c:\Users\eivin\Documents\Skule\FPGA\dataprosjekt-gr2-FPGA")
DEBUG = REPO / r"vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt"
NPZ = REPO / r"model/intermediate_values.npz"
Q_SCALE = 64

# parse last FC1_OUTPUT block
fc1_blocks = []
pat_header = re.compile(r'^FC1_OUTPUT:', flags=re.M)
pat_neuron = re.compile(r'^\s*Neuron[_ ]?(\d+)\s*:\s*([0-9A-Fa-fx\-]+)')
with DEBUG.open('r', encoding='utf-8', errors='ignore') as f:
    cur = None
    for line in f:
        if line.strip().startswith('FC1_OUTPUT:'):
            cur = {}
            fc1_blocks.append(cur)
            continue
        if cur is not None:
            m = pat_neuron.match(line)
            if m:
                idx = int(m.group(1))
                raw = m.group(2)
                # parse int (dec or 0xhex)
                try:
                    val = int(raw, 0) if not raw.lower().startswith('0x') else int(raw, 16)
                except Exception:
                    val = int(re.sub('[^0-9\-]', '', raw) or '0')
                # sign-correct for 16-bit
                if val > 32767:
                    val = val - 65536
                cur[idx] = val

if not fc1_blocks:
    print('No FC1_OUTPUT in debug file')
    raise SystemExit(1)

vhdl = fc1_blocks[-1]
# load python npz q1.6 ints
arr = np.load(NPZ)
if 'layer_5_output' not in arr:
    print('layer_5_output missing in npz; keys:', arr.files)
    raise SystemExit(1)
py = arr['layer_5_output']
py_qints = np.round(py * Q_SCALE).astype(int)

# Build arrays
vhdl_raw = [vhdl.get(i, 0) for i in range(64)]
vhdl_final_guess = []
for v in vhdl_raw:
    # manual script logic: if abs(v) > 127 treat as raw accumulator -> final = v // Q_SCALE
    if abs(v) > 127:
        final = int((v + (Q_SCALE//2 if v>=0 else -Q_SCALE//2)) // Q_SCALE)
    else:
        final = v
    # Apply ReLU and 8-bit saturation (as FC1 does)
    final = max(0, min(127, final))
    vhdl_final_guess.append(final)

# Compare
diffs = [int(py_qints[i] - vhdl_final_guess[i]) for i in range(64)]
abs_diffs = [abs(d) for d in diffs]
print('Neuron | py_qint | vhdl_final_guess | diff')
for i in range(64):
    if i < 20 or abs_diffs[i] > 0:
        print(f'{i:6d} | {py_qints[i]:7d} | {vhdl_final_guess[i]:16d} | {diffs[i]:5d}')

print('\nSummary:')
print('  total nonzero diffs:', sum(1 for d in diffs if d != 0))
print('  avg abs diff  :', sum(abs_diffs)/len(abs_diffs))
print('  max abs diff  :', max(abs_diffs))

# optional: save comparison
out = REPO / 'testbench_logs' / 'fc1_npz_vhdl_comparison.txt'
out.parent.mkdir(exist_ok=True, parents=True)
with out.open('w') as f:
    f.write('i,py_qint,vhdl_final_guess,diff\n')
    for i in range(64):
        f.write(f'{i},{py_qints[i]},{vhdl_final_guess[i]},{diffs[i]}\n')
print('Saved comparison to', out)
