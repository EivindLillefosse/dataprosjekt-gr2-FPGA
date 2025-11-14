#!/usr/bin/env python3
import re
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parent.parent
NPZ = REPO / 'model' / 'intermediate_values.npz'
WE = REPO / 'model' / 'fpga_weights_and_bias' / 'layer_6_dense_1_weights.coe'
BI = REPO / 'model' / 'fpga_weights_and_bias' / 'layer_6_dense_1_biases.coe'
Q = 64
NEURON = 6

def parse_coe(path: Path):
    txt = path.read_text()
    m = re.search(r'memory_initialization_vector\s*=\s*(.*);', txt, flags=re.S)
    if not m:
        raise RuntimeError('Failed to parse COE: ' + str(path))
    parts = [p.strip() for p in m.group(1).replace('\n','').split(',') if p.strip()]
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

def load_layer5_from_npz():
    data = np.load(NPZ)
    key = None
    for k in ('layer_5_output','layer_5_out','layer_5'):
        if k in data:
            key = k; break
    if key is None:
        for k in data.files:
            a = data[k]
            if hasattr(a,'shape') and a.ndim == 1 and a.shape[0] == 64:
                key = k; break
    if key is None:
        raise RuntimeError('Could not find layer_5_output in npz')
    arr = data[key]
    arr_q = (arr * Q).round().astype(int)
    inputs = [int(x) for x in arr_q]
    return inputs

def main():
    weights = parse_coe(WE)
    inputs = load_layer5_from_npz()
    running = 0
    print('First 12 multiplications for FC2 neuron', NEURON)
    for i in range(12):
        x = inputs[i]
        w = weights[i][NEURON] if NEURON < len(weights[i]) else 0
        p = x * w
        running += p
        print(f'  idx {i:03d}: input={x:4d} weight={w:4d} prod={p:7d} -> running={running:7d}')
    print('\nPartial sum after 12 =', running)
    # bias
    m = re.search(r'memory_initialization_vector\s*=\s*(.*);', (REPO/'model'/'fpga_weights_and_bias'/'layer_6_dense_1_biases.coe').read_text(), flags=re.S)
    parts = [p.strip() for p in m.group(1).replace('\n','').split(',') if p.strip()]
    # take neuron bias
    # Bias parsing shortcut: assume each token is one bias byte
    bias_tokens = []
    for p in parts:
        hexchars = re.sub(r'[^0-9A-Fa-f]','',p)
        if hexchars:
            if len(hexchars)%2: hexchars='0'+hexchars
            b=[int(hexchars[i:i+2],16) for i in range(0,len(hexchars),2)]
        else:
            v=int(p,0); b=[]
            while v: b.append(v&0xFF); v>>=8
        for v in b: bias_tokens.append(v-256 if v>=128 else v)
    bias = bias_tokens[NEURON]
    print('Bias (Q1.6) =', bias, '-> bias*64 =', bias*Q)
    acc_with_bias = running + bias*Q
    final = int((acc_with_bias + (Q//2 if acc_with_bias >= 0 else -Q//2)) // Q)
    q = max(0, min(127, max(-128, final)))
    print('acc_with_bias (partial) =', acc_with_bias)
    print('final_int (partial) =', final)
    print('q after ReLU (partial) =', q)

if __name__ == '__main__':
    main()
