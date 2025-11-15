#!/usr/bin/env python3
from pathlib import Path
import numpy as np
# Values taken from your compute_fc1_manual.py output in the prompt for NORMAL byte order
manual_normal = {
    1: 9632,
    5: 31804,
    10: 319,
    11: 25736,
    14: 27571,
    15: 771,
    20: 898,
    32: 17610,
    35: 4447,
    37: 702,
}
# For REVERSED case the vhdl_raw were the same numbers printed by the script, so we can reuse them.
REPO = Path(r"c:\Users\eivin\Documents\Skule\FPGA\dataprosjekt-gr2-FPGA")
npz = REPO / 'model' / 'intermediate_values.npz'
arr = np.load(npz)
fc1 = arr['layer_5_output']
Q_SCALE = 64
print('Neuron | python_float | q1.6_int | q1.6_float | manual_vhdl_raw | from_raw_as_acc_guess | from_raw_as_final_guess')
for n in [1,5,10,11,14,15,20,32,35,37]:
    py = float(fc1[n])
    qint = int(round(py * Q_SCALE))
    qfloat = qint / Q_SCALE
    vraw = manual_normal[n]
    # compute what the manual script guessed: if abs(vraw)>127 they treat as raw accumulator; else final*Q_SCALE
    if abs(vraw) > 127:
        vhdl_acc_guess = vraw
        vhdl_final_guess = vraw // Q_SCALE
    else:
        vhdl_acc_guess = vraw * Q_SCALE
        vhdl_final_guess = vraw
    print(f'{n:6d} | {py:12.6f} | {qint:8d} | {qfloat:10.6f} | {vraw:14d} | {vhdl_acc_guess:19d} | {vhdl_final_guess:18d}')

# summary stats
py_qints = (fc1 * Q_SCALE).round().astype(int)
print('\nPython FC1 q1.6 ints (first 20):', py_qints[:20])
print('Python FC1 min/max:', py_qints.min(), py_qints.max())
print('Done')
