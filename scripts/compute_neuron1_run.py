#!/usr/bin/env python3
"""
compute_neuron1_run.py

Quick runner to compute FC1 neuron 1 (index 1) using:
 - Python Pool2 values from model/intermediate_values.npz
 - Weights from COE (model/fpga_weights_and_bias/layer_5_dense_weights.coe)
 - Biases from COE (model/fpga_weights_and_bias/layer_5_dense_biases.coe)
 - Optionally weights from saved Python model (model/saved_model) if available

Prints accumulator (Q2.12-like), rounded final integer (Q1.6), and clipped ReLU output.
"""

from pathlib import Path
import re
import numpy as np

REPO = Path(__file__).resolve().parent.parent
NPZ_FILE = REPO / 'model' / 'intermediate_values.npz'
WEIGHTS_COE = REPO / 'model' / 'fpga_weights_and_bias' / 'layer_5_dense_weights.coe'
BIAS_COE = REPO / 'model' / 'fpga_weights_and_bias' / 'layer_5_dense_biases.coe'
DEBUG_FILE = REPO / 'vivado_project' / 'CNN.sim' / 'sim_1' / 'behav' / 'xsim' / 'cnn_intermediate_debug.txt'

INPUT_SPATIAL = 5
INPUT_CHANNELS = 16
N_INPUTS = INPUT_SPATIAL * INPUT_SPATIAL * INPUT_CHANNELS
N_NEURONS = 64
Q_SCALE = 64


def parse_coe_vector(path: Path):
    txt = path.read_text(errors='ignore')
    m = re.search(r"memory_initialization_vector\s*=\s*(.*);", txt, flags=re.S)
    if not m:
        lines = [l.strip() for l in txt.splitlines() if l.strip() and not l.strip().startswith(';')]
        for i, ln in enumerate(lines):
            if ln.lower().startswith('memory_initialization_vector'):
                rest = '\n'.join(lines[i:])
                if '=' in rest:
                    vec = rest.split('=', 1)[1].strip().rstrip(';')
                    parts = [p.strip() for p in vec.replace('\n', '').split(',') if p.strip()]
                    return parts
        raise RuntimeError(f'No memory_initialization_vector in {path}')
    vec = m.group(1).replace('\n', '').replace('\r', '')
    parts = [p.strip() for p in vec.split(',') if p.strip()]
    return parts


def coe_address_bytes(token: str):
    hexchars = re.sub(r'[^0-9A-Fa-f]', '', token)
    if hexchars:
        if len(hexchars) % 2:
            hexchars = '0' + hexchars
        return [int(hexchars[i:i+2], 16) for i in range(0, len(hexchars), 2)]
    try:
        v = int(token, 0)
        b = []
        while v:
            b.append(v & 0xFF)
            v >>= 8
        return list(reversed(b)) if b else [0]
    except Exception:
        return [0]


def load_weights_coe():
    parts = parse_coe_vector(WEIGHTS_COE)
    addrs = []
    for p in parts:
        b = coe_address_bytes(p)
        signed = [x - 256 if x >= 128 else x for x in b]
        addrs.append(signed)
    return addrs


def load_biases():
    parts = parse_coe_vector(BIAS_COE)
    bs = []
    for p in parts:
        b = coe_address_bytes(p)
        for v in b:
            bs.append(v - 256 if v >= 128 else v)
    return bs


def load_pool2_from_npz():
    if not NPZ_FILE.exists():
        raise FileNotFoundError('NPZ not found: ' + str(NPZ_FILE))
    data = np.load(NPZ_FILE)
    key = None
    for k in ('layer_3_output', 'layer_3_out', 'layer_3', 'layer_3_pool2_output'):
        if k in data:
            key = k
            break
    if key is None:
        for k in data.files:
            a = data[k]
            if hasattr(a, 'shape') and a.ndim == 3 and a.shape[0] == 5 and a.shape[1] == 5 and a.shape[2] == INPUT_CHANNELS:
                key = k
                break
    if key is None:
        raise RuntimeError('Could not locate pool2 output in npz; keys=' + ','.join(data.files))
    arr = data[key]
    arr_q = (arr * Q_SCALE).round().astype(int)
    inputs = []
    for r in range(arr_q.shape[0]):
        for c in range(arr_q.shape[1]):
            for ch in range(arr_q.shape[2]):
                inputs.append(int(arr_q[r, c, ch]))
    if len(inputs) != N_INPUTS:
        print('Warning: expected', N_INPUTS, 'inputs got', len(inputs))
    return inputs


def parse_pool2_from_vivado():
    path = DEBUG_FILE
    if not path.exists():
        raise FileNotFoundError('Debug file not found: ' + str(path))
    pool2 = {}
    pat = re.compile(r'^LAYER3_POOL2_OUTPUT:\s*\[(\d+),(\d+)\]')
    filter_re = re.compile(r'^[\s]*Filter[_ ]?(\d+)\s*:\s*([0-9A-Fa-fx\-]+)')
    current = None
    with path.open('r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            m = pat.match(line)
            if m:
                r = int(m.group(1)); c = int(m.group(2))
                current = (r, c)
                pool2[current] = {}
                continue
            if current is not None:
                m2 = filter_re.match(line)
                if m2:
                    idx = int(m2.group(1))
                    raw = m2.group(2)
                    try:
                        val = int(raw, 0) if not raw.lower().startswith('0x') else int(raw, 16)
                    except Exception:
                        s = re.sub(r'[^0-9a-fA-F\-xX]', '', raw)
                        val = int(s, 0) if s else 0
                    if val >= 128 and val <= 255:
                        val = val - 256
                    pool2[current][idx] = val
    inputs = []
    for r in range(INPUT_SPATIAL):
        for c in range(INPUT_SPATIAL):
            blk = pool2.get((r, c), {})
            for ch in range(INPUT_CHANNELS):
                inputs.append(blk.get(ch, 0))
    if len(inputs) != N_INPUTS:
        print('Warning: expected', N_INPUTS, 'inputs got', len(inputs))
    return inputs


def compute_neuron(neuron: int, inputs: list, weights_addrs: list, biases: list):
    w_col = []
    for i in range(N_INPUTS):
        if i < len(weights_addrs):
            addr = weights_addrs[i]
            w = addr[neuron] if neuron < len(addr) else 0
        else:
            w = 0
        w_col.append(w)
    acc = 0
    for x, w in zip(inputs, w_col):
        acc += x * w
    bias = biases[neuron] if neuron < len(biases) else 0
    acc_with_bias = acc + bias * Q_SCALE
    final_round = int((acc_with_bias + (Q_SCALE // 2 if acc_with_bias >= 0 else -Q_SCALE // 2)) // Q_SCALE)
    q = max(0, max(-128, min(127, final_round)))
    return acc_with_bias, final_round, q


def try_load_python_weights():
    sm = REPO / 'model' / 'saved_model'
    if not sm.exists():
        return None
    try:
        import tensorflow as tf
    except Exception:
        return None
    model = tf.keras.models.load_model(str(sm))
    dense = None
    for layer in model.layers:
        if hasattr(layer, 'units') and getattr(layer, 'units') == N_NEURONS:
            dense = layer
            break
    if dense is None:
        return None
    w = dense.get_weights()[0]
    w_q = (w * Q_SCALE).round().astype(int).clip(-128, 127)
    addrs = []
    for i in range(w_q.shape[0]):
        addrs.append([int(x) for x in w_q[i]])
    return addrs


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', choices=['python', 'vhdl'], default='python', help='Input source for Pool2 values')
    parser.add_argument('--compare', action='store_true', help='Compare python NPZ pool2 vs VHDL pool2 and exit')
    args = parser.parse_args()

    neuron = 1
    if args.compare:
        py_inputs = load_pool2_from_npz()
        vhdl_inputs = parse_pool2_from_vivado()
        import numpy as _np
        a = _np.array(py_inputs, dtype=int)
        b = _np.array(vhdl_inputs, dtype=int)
        if a.shape != b.shape:
            print('Input shapes differ: python', a.shape, 'vhdl', b.shape)
        diff = a - b
        absdiff = _np.abs(diff)
        print('Comparison python vs vhdl pool2:')
        print('  count:', a.size)
        print('  mean abs diff:', float(_np.mean(absdiff)))
        print('  max abs diff:', int(_np.max(absdiff)))
        # show top 10 mismatches
        idx = _np.argsort(-absdiff)[:10]
        print('  top mismatches (index, py, vhdl, diff):')
        for i in idx:
            print(f'   {i:03d}: {int(a[i])} vs {int(b[i])} -> {int(diff[i])}')
        return

    if args.source == 'python':
        inputs = load_pool2_from_npz()
    else:
        inputs = parse_pool2_from_vivado()
    print('Loaded inputs length', len(inputs))
    weights_coe = load_weights_coe()
    biases = load_biases()
    print('Loaded COE weights addresses:', len(weights_coe), 'biases:', len(biases))
    acc, final_int, q = compute_neuron(neuron, inputs, weights_coe, biases)
    print('\nCOE weights result for neuron', neuron)
    print('  acc (raw) =', acc)
    print('  final_int (Q1.6) =', final_int)
    print('  q1.6 after ReLU/clamp =', q)

    py_weights = try_load_python_weights()
    if py_weights is not None:
        acc2, final_int2, q2 = compute_neuron(neuron, inputs, py_weights, biases)
        print('\nPython saved model weights result for neuron', neuron)
        print('  acc (raw) =', acc2)
        print('  final_int (Q1.6) =', final_int2)
        print('  q1.6 after ReLU/clamp =', q2)
    else:
        print('\nNo Python saved_model weights available or TensorFlow not installed; skipped')


if __name__ == '__main__':
    main()
