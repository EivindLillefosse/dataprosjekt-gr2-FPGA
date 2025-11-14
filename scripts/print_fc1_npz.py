#!/usr/bin/env python3
from pathlib import Path
import numpy as np
REPO = Path(r"c:\Users\eivin\Documents\Skule\FPGA\dataprosjekt-gr2-FPGA")
npz = REPO / 'model' / 'intermediate_values.npz'
if not npz.exists():
    print('intermediate_values.npz not found at', npz)
    raise SystemExit(1)
arr = np.load(npz)
print('Available keys:')
for k in arr.files:
    print(' -', k)
# Try common keys
for key in ['layer_5_output', 'layer_5_out', 'layer_5_dense', 'fc1_output', 'layer_5']:
    if key in arr:
        data = arr[key]
        print(f'\nKey: {key} shape={data.shape} dtype={data.dtype}')
        print('First 20 values:', data.flatten()[:20])
        print('min/max/mean/std:', data.min(), data.max(), data.mean(), data.std())
        break
else:
    print('\nNo expected FC1 key found. Showing all scalar/1D arrays under 200 elements:')
    for k in arr.files:
        d = arr[k]
        if d.ndim == 1 and d.size <= 200:
            print(f'Key {k}: shape={d.shape} sample={d[:20]}')

print('\nDone')
