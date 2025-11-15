#!/usr/bin/env python3
import re
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parent.parent
NPZ = REPO / 'model' / 'intermediate_values.npz'
WE = REPO / 'model' / 'fpga_weights_and_bias' / 'layer_5_dense_weights.coe'
BI = REPO / 'model' / 'fpga_weights_and_bias' / 'layer_5_dense_biases.coe'
Q = 64
NEURON = 6

def parse_coe(path: Path):
    txt = path.read_text()
    m = re.search(r'memory_initialization_vector\s*=\s*(.*);', txt, flags=re.S)
    if m:
        parts = [p.strip() for p in m.group(1).replace('\n','').split(',') if p.strip()]
    else:
        lines = [l.strip() for l in txt.splitlines() if l.strip() and not l.strip().startswith(';')]
        parts = []
        for i, ln in enumerate(lines):
            if ln.lower().startswith('memory_initialization_vector'):
                rest = '\n'.join(lines[i:])
                parts = [p.strip() for p in rest.split('=',1)[1].replace('\n','').rstrip(';').split(',') if p.strip()]
                break
    addrs = []
    for p in parts:
        hexchars = re.sub(r'[^0-9A-Fa-f]','',p)
        if hexchars:
            if len(hexchars) % 2:
                hexchars = '0' + hexchars
            b = [int(hexchars[i:i+2],16) for i in range(0,len(hexchars),2)]
        else:
            v = int(p,0); b = []
            while v: b.append(v & 0xFF); v >>= 8
            b = list(reversed(b)) if b else [0]
        signed = [x - 256 if x >= 128 else x for x in b]
        addrs.append(signed)
    return addrs

def load_biases(path: Path):
    txt = path.read_text()
    m = re.search(r'memory_initialization_vector\s*=\s*(.*);', txt, flags=re.S)
    parts = [p.strip() for p in m.group(1).replace('\n','').split(',') if p.strip()]
    bs = []
    for p in parts:
        hexchars = re.sub(r'[^0-9A-Fa-f]','',p)
        if hexchars:
            if len(hexchars) % 2:
                hexchars = '0' + hexchars
            b = [int(hexchars[i:i+2],16) for i in range(0,len(hexchars),2)]
        else:
            v = int(p,0); b = []
            while v: b.append(v & 0xFF); v >>= 8
        for v in b: bs.append(v - 256 if v >= 128 else v)
    return bs

def load_npz_pool2():
    data = np.load(NPZ)
    arr = None
    for k in ('layer_3_output','layer_3_out','layer_3','layer_3_pool2_output'):
        if k in data:
            arr = data[k]
            break
    if arr is None:
        for k in data.files:
            a = data[k]
            if hasattr(a,'shape') and a.ndim == 3 and a.shape == (5,5,16):
                arr = a
                break
    if arr is None:
        raise RuntimeError('Could not find pool2 in npz')
    arr_q = (arr * Q).round().astype(int)
    inputs = [int(arr_q[r,c,ch]) for r in range(5) for c in range(5) for ch in range(16)]
    return inputs

def main():
    weights = parse_coe(WE)
    biases = load_biases(BI)
    inputs = load_npz_pool2()
    running = 0
    print('Showing first 12 multiplications (input * weight) and running sum for neuron', NEURON)
    print('format: idx (r,c,ch): input x weight = product -> running_sum')
    for i in range(12):
        x = inputs[i]
        w = weights[i][NEURON] if NEURON < len(weights[i]) else 0
        p = x * w
        running += p
        r = i // (16*5)
        rem = i % (16*5)
        c = rem // 16
        ch = rem % 16
        print(f'  idx {i:03d} (r{r},c{c},ch{ch}): {x} x {w} = {p:6d} -> running {running:6d}')
    bias = biases[NEURON]
    print('\nAfter first 12 items, partial sum =', running)
    print('Bias (Q1.6) =', bias, '-> bias*64 =', bias*Q)
    acc_with_bias = running + bias*Q
    final = int((acc_with_bias + (Q//2 if acc_with_bias >= 0 else -Q//2)) // Q)
    q = max(0, min(127, max(-128, final)))
    print('acc_with_bias (partial) =', acc_with_bias)
    print('final_int (Q1.6, partial) =', final)
    print('q after ReLU (partial) =', q)

if __name__ == '__main__':
    main()
