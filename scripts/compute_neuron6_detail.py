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
            v = int(p,0)
            b = []
            while v:
                b.append(v & 0xFF)
                v >>= 8
            b = list(reversed(b)) if b else [0]
        signed = [x - 256 if x >= 128 else x for x in b]
        addrs.append(signed)
    return addrs

def load_biases(path: Path):
    txt = path.read_text()
    m = re.search(r'memory_initialization_vector\s*=\s*(.*);', txt, flags=re.S)
    if not m:
        raise RuntimeError('bias coe parse failed')
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
        for v in b:
            bs.append(v - 256 if v >= 128 else v)
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
    contribs = []
    acc = 0
    for i, x in enumerate(inputs):
        w = weights[i][NEURON] if NEURON < len(weights[i]) else 0
        prod = x * w
        contribs.append((i, x, w, prod))
        acc += prod
    bias = biases[NEURON]
    acc_with_bias = acc + bias * Q
    final = int((acc_with_bias + (Q//2 if acc_with_bias >= 0 else -Q//2)) // Q)
    q = max(0, min(127, max(-128, final)))
    contribs_sorted = sorted(contribs, key=lambda t: abs(t[3]), reverse=True)
    print(f'Neuron {NEURON} manual calc using NPZ pool2:')
    print('  raw accumulator (sum x*w) =', acc)
    print('  bias (Q1.6) =', bias, '-> bias*64 =', bias * Q)
    print('  acc_with_bias =', acc_with_bias)
    print('  final_int (Q1.6) =', final)
    print('  q after ReLU/clamp =', q)
    print('\nTop 20 input contributions (idx, r,c,ch, input, weight, product):')
    for i, x, w, p in contribs_sorted[:20]:
        r = i // (16*5)
        rem = i % (16*5)
        c = rem // 16
        ch = rem % 16
        print(f'  idx {i:03d} (r{r},c{c},ch{ch}): input={x:4d} weight={w:4d} prod={p:7d}')

if __name__ == '__main__':
    main()
