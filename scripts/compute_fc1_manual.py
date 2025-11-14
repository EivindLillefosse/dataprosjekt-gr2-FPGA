#!/usr/bin/env python3
"""
compute_fc1_manual.py

Clean, single-file manual FC1 verification helper. It:
 - parses the layer_5 dense weights and biases COE files
 - extracts the last LAYER3_POOL2_OUTPUT block from the Vivado debug log
 - computes selected FC1 neuron accumulators in Q2.12 and converts to Q1.6
 - compares the computed values with the last FC1_OUTPUT block in the debug log

Run from repo root. Paths are the project's defaults; adjust REPO if needed.
"""

import re
from pathlib import Path
from typing import List, Tuple
import sys
import json
from pathlib import Path
import numpy as np

REPO = Path(r"c:\Users\eivin\Documents\Skule\FPGA\dataprosjekt-gr2-FPGA")
DEBUG_FILE = REPO / r"vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt"
WEIGHTS_COE = REPO / r"model/fpga_weights_and_bias/layer_5_dense_weights.coe"
BIAS_COE = REPO / r"model/fpga_weights_and_bias/layer_5_dense_biases.coe"
NPZ_FILE = REPO / r"model/intermediate_values.npz"
SAVED_MODEL_DIR = REPO / r"model/saved_model"

# Layer constants
INPUT_SPATIAL = 5
INPUT_CHANNELS = 16
N_INPUTS = INPUT_SPATIAL * INPUT_SPATIAL * INPUT_CHANNELS  # 400
N_NEURONS = 64
Q_SCALE = 64  # Q1.6


def parse_coe_vector(path: Path) -> List[str]:
    txt = path.read_text(errors='ignore')
    m = re.search(r"memory_initialization_vector\s*=\s*(.*);", txt, flags=re.S)
    if not m:
        # fallback: remove comment lines and try to find the vector line
        lines = [l.strip() for l in txt.splitlines() if l.strip() and not l.strip().startswith(';')]
        for i, ln in enumerate(lines):
            if ln.lower().startswith('memory_initialization_vector'):
                rest = '\n'.join(lines[i:])
                if '=' in rest:
                    vec = rest.split('=', 1)[1].strip().rstrip(';')
                    parts = [p.strip() for p in vec.replace('\n', '').split(',') if p.strip()]
                    return parts
        raise RuntimeError(f'No memory_initialization_vector in {path}')
    vec = m.group(1)
    vec = vec.replace('\n', '').replace('\r', '')
    parts = [p.strip() for p in vec.split(',') if p.strip()]
    return parts


def coe_address_bytes(token: str) -> List[int]:
    # Accept tokens like 0x..., <hexdata>, or decimals; extract hex chars if present
    hexchars = re.sub(r'[^0-9A-Fa-f]', '', token)
    if hexchars:
        if len(hexchars) % 2:
            hexchars = '0' + hexchars
        return [int(hexchars[i:i+2], 16) for i in range(0, len(hexchars), 2)]
    # fallback: try decimal integer
    try:
        v = int(token, 0)
        # convert to bytes little-endian
        b = []
        while v:
            b.append(v & 0xFF)
            v >>= 8
        return list(reversed(b)) if b else [0]
    except Exception:
        return [0]


def load_weights(reverse_bytes: bool = False) -> List[List[int]]:
    parts = parse_coe_vector(WEIGHTS_COE)
    addrs: List[List[int]] = []
    for p in parts:
        b = coe_address_bytes(p)
        # Optionally reverse byte order to test MSB-first vs LSB-first
        if reverse_bytes:
            b = list(reversed(b))
        # convert to signed 8-bit
        signed = [x - 256 if x >= 128 else x for x in b]
        addrs.append(signed)
    if len(addrs) < N_INPUTS:
        print(f'Warning: found {len(addrs)} weight addresses, expected {N_INPUTS}')
    return addrs


def load_weights_from_python_model() -> List[List[int]]:
    """Load Dense layer weights (400,64) from the saved Keras model if available.
    Returns weights organized as list of 400 addresses, each a list of 64 signed int8 weights.
    If TensorFlow is not available or the model doesn't contain the dense layer, raise RuntimeError."""
    try:
        import tensorflow as tf
    except Exception as e:
        raise RuntimeError('TensorFlow not available to load python weights: ' + str(e))

    # Try loading the saved model and find the Dense layer with 64 units
    model = tf.keras.models.load_model(str(SAVED_MODEL_DIR))
    # Find first Dense layer with 64 units
    dense = None
    for layer in model.layers:
        if hasattr(layer, 'units') and getattr(layer, 'units') == N_NEURONS:
            dense = layer
            break
    if dense is None:
        raise RuntimeError('Could not find Dense layer with 64 units in saved model')

    # weights[0] is weight matrix shape (in_features, out_features)
    w = dense.get_weights()[0]  # numpy array shape (400,64)
    # Quantized weights should be in Q1.6; convert to signed int8 by rounding
    w_q = (w * Q_SCALE).round().astype(int)
    # Clip to int8 range
    w_q = w_q.clip(-128, 127)
    addrs: List[List[int]] = []
    for i in range(w_q.shape[0]):
        row = [int(x) for x in w_q[i]]
        addrs.append(row)
    return addrs


def load_biases() -> List[int]:
    parts = parse_coe_vector(BIAS_COE)
    bs: List[int] = []
    for p in parts:
        b = coe_address_bytes(p)
        for v in b:
            bs.append(v - 256 if v >= 128 else v)
    return bs


def parse_pool2(debug_path: Path) -> dict:
    # returns mapping (r,c) -> {ch: val}
    pool2 = {}
    pat = re.compile(r'^LAYER3_POOL2_OUTPUT:\s*\[(\d+),(\d+)\]')
    filter_re = re.compile(r'^[\s]*Filter[_ ]?(\d+)\s*:\s*([0-9A-Fa-fx\-]+)')
    current = None
    if not debug_path.exists():
        raise FileNotFoundError(f"Debug file not found: {debug_path}")
    with debug_path.open('r', encoding='utf-8', errors='ignore') as f:
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
                    # interpret as signed 8-bit if needed
                    if val >= 128 and val <= 255:
                        val = val - 256
                    pool2[current][idx] = val
    return pool2


def load_pool2_from_npz(npz_path: Path) -> dict:
    """Return pool2 mapping (r,c) -> {ch: val} extracted from model/intermediate_values.npz
    Assumes Python saved keys use naming like 'layer_3_output' or similar. The script will try 'layer_3_output'.
    Values in NPZ are floating-point activations; convert to integer Q1.6 by rounding.
    """
    if not npz_path.exists():
        raise FileNotFoundError(f'NPZ file not found: {npz_path}')
    import numpy as np
    data = np.load(npz_path)
    key = None
    for k in ('layer_3_output', 'layer_3_out', 'layer_3', 'layer_3_pool2_output'):
        if k in data:
            key = k
            break
    if key is None:
        # try heuristic: find a 5x5x16 array matching Pool2 shape
        for k in data.files:
            a = data[k]
            if hasattr(a, 'shape') and a.ndim == 3 and a.shape[0] == 5 and a.shape[1] == 5 and a.shape[2] == INPUT_CHANNELS:
                key = k
                break
    if key is None:
        raise RuntimeError('Could not locate pool2 output in npz; keys=' + ','.join(data.files))

    arr = data[key]  # shape (5,5,16)
    # Convert floats to integer-like values (assume already Q1.6 float outputs)
    arr_q = (arr * Q_SCALE).round().astype(int)
    pool2 = {}
    for r in range(arr_q.shape[0]):
        for c in range(arr_q.shape[1]):
            pool2[(r, c)] = {ch: int(arr_q[r, c, ch]) for ch in range(arr_q.shape[2])}
    return pool2


def build_input_vector(pool2: dict) -> List[int]:
    inputs: List[int] = []
    missing = 0
    for r in range(INPUT_SPATIAL):
        for c in range(INPUT_SPATIAL):
            blk = pool2.get((r, c), {})
            for ch in range(INPUT_CHANNELS):
                v = blk.get(ch, None)
                if v is None:
                    missing += 1
                    v = 0
                inputs.append(v)
    if missing:
        print(f'Warning: missing {missing} pool2 values; using zeros', file=sys.stderr)
    return inputs


def parse_fc1_block(debug_path: Path) -> dict:
    # return last FC1_OUTPUT block as {neuron: raw_val}
    fc1_blocks = []
    if not debug_path.exists():
        raise FileNotFoundError(f"Debug file not found: {debug_path}")
    with debug_path.open('r', encoding='utf-8', errors='ignore') as f:
        cur = None
        for line in f:
            if line.strip().startswith('FC1_OUTPUT:'):
                cur = {}
                fc1_blocks.append(cur)
                continue
            if cur is not None:
                m = re.match(r'^\s*Neuron[_ ]?(\d+)\s*:\s*([0-9A-Fa-fx\-]+)', line)
                if m:
                    idx = int(m.group(1)); raw = m.group(2)
                    try:
                        val = int(raw, 0) if not raw.lower().startswith('0x') else int(raw, 16)
                    except Exception:
                        val = int(re.sub('[^0-9\-]', '', raw) or '0')
                    # Interpret 16-bit signed if value looks wrapped
                    if val > 32767:
                        val = val - 65536
                    cur[idx] = val
    return fc1_blocks[-1] if fc1_blocks else {}


def compute_neuron(neuron: int, inputs: List[int], weights_addrs: List[List[int]], biases: List[int]) -> Tuple[int, int, int]:
    # Build weight column for neuron: weight for input i is weights_addrs[i][neuron]
    w_col: List[int] = []
    for i in range(N_INPUTS):
        if i < len(weights_addrs):
            addr = weights_addrs[i]
            w = addr[neuron] if neuron < len(addr) else 0
        else:
            w = 0
        w_col.append(w)

    acc = 0  # accumulator in raw units (x * w summed)
    for x, w in zip(inputs, w_col):
        acc += x * w
    bias = biases[neuron] if neuron < len(biases) else 0
    # bias is in Q1.6; convert to accumulator scale by *Q_SCALE
    acc_with_bias = acc + bias * Q_SCALE

    # convert accumulator (Q2.12 like) back to Q1.6 integer with rounding
    final_round = int((acc_with_bias + (Q_SCALE // 2 if acc_with_bias >= 0 else -Q_SCALE // 2)) // Q_SCALE)
    # apply ReLU (assuming FC1 uses ReLU) and saturate to signed 8-bit
    q = max(0, max(-128, min(127, final_round)))
    return acc_with_bias, final_round, q


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Compute FC1 manually and compare various data sources')
    parser.add_argument('--no-tf', action='store_true', help='Do not attempt to load TensorFlow/saved model weights')
    parser.add_argument('--py-vs-py', action='store_true', help='Run full report comparing Python weights vs Python inputs')
    parser.add_argument('--simple', action='store_true', help='Print compact, easy-to-read comparison output')
    args = parser.parse_args()

    # Load COE-based weights (both normal and reversed) and biases
    print('Loading COE weights (normal byte order)')
    coe_weights = load_weights(reverse_bytes=False)
    print('Loading COE weights (reversed byte order)')
    coe_weights_rev = load_weights(reverse_bytes=True)
    biases = load_biases()
    print(f'Loaded biases: {len(biases)}')

    # Load python weights if requested
    py_weights = None
    if not args.no_tf:
        try:
            print('Attempting to load weights from Python saved model...')
            py_weights = load_weights_from_python_model()
            print('Loaded Python model weights (shape preview):', len(py_weights), 'addresses')
        except Exception as e:
            print('Could not load Python model weights:', e)

    # Load inputs: VHDL pool2 and Python pool2
    print('Parsing Pool2 from VHDL debug...')
    vhdl_pool2 = parse_pool2(DEBUG_FILE)
    print('Building input vector from VHDL pool2...')
    vhdl_inputs = build_input_vector(vhdl_pool2)

    py_pool2 = None
    try:
        print('Parsing Pool2 from Python NPZ...')
        py_pool2 = load_pool2_from_npz(NPZ_FILE)
        py_inputs = build_input_vector(py_pool2)
    except Exception as e:
        print('Could not load Pool2 from NPZ:', e)
        py_inputs = None

    # Prepare comparisons to run
    combos = []
    combos.append(('COE', 'VHDL', coe_weights, vhdl_inputs))
    combos.append(('COE', 'PY', coe_weights, py_inputs))
    if py_weights is not None:
        combos.append(('PY', 'VHDL', py_weights, vhdl_inputs))
        combos.append(('PY', 'PY', py_weights, py_inputs))

        # Optional full-report: Python-weights vs Python-inputs compared to Python NPZ reference
        if args.py_vs_py:
            # try to get python weights
            try:
                py_weights_addrs = load_weights_from_python_model()
            except Exception as e:
                print("Failed to load python model weights for full report:", e)
                return

            print("\nRunning full PY-vs-PY report (all neurons)...")
            # load inputs from npz
            pool2_py = load_pool2_from_npz(NPZ_FILE)
            inputs_py = build_input_vector(pool2_py)

            # Load python reference final outputs from NPZ and quantize to Q1.6
            npz = np.load(NPZ_FILE, allow_pickle=True)
            # try common keys for layer_5 output
            ref_keys = [k for k in npz.files if 'layer_5' in k or 'layer5' in k or 'layer_5_output' in k]
            if len(ref_keys) == 0:
                # fallback to any 64-length array
                ref_key = None
                for k in npz.files:
                    a = npz[k]
                    if hasattr(a, 'shape') and a.shape == (64,):
                        ref_key = k
                        break
            else:
                ref_key = ref_keys[0]

            if ref_key is None:
                print('Could not find python FC1 reference array in NPZ; aborting full report')
                return

            ref = npz[ref_key].astype(float)
            q_scale = 64.0
            ref_q = np.rint(ref * q_scale).astype(int)
            ref_q = np.clip(ref_q, -128, 127)

            rows = []
            abs_diffs = []
            for neuron in range(64):
                acc, final_int, q1_6 = compute_neuron(neuron, inputs_py, py_weights_addrs, biases)
                ref_val = int(ref_q[neuron])
                diff = int(q1_6) - ref_val
                abs_diffs.append(abs(diff))
                rows.append((neuron, acc, final_int, q1_6, ref_val, diff))

            avg_abs = float(np.mean(abs_diffs))
            max_abs = int(np.max(abs_diffs))
            eq_count = sum(1 for d in abs_diffs if d == 0)

            out_csv = Path('testbench_logs') / 'py_weights_py_inputs_vs_python_ref.csv'
            out_csv.parent.mkdir(parents=True, exist_ok=True)
            with open(out_csv, 'w') as f:
                f.write('neuron,acc,final_int,q1_6,python_ref_q1_6,diff\n')
                for r in rows:
                    f.write('%d,%d,%d,%d,%d,%d\n' % r)

            print(f'PY-vs-PY report saved to {out_csv}')
            print(f'Equality count: {eq_count}/64; avg abs diff: {avg_abs:.3f}; max abs diff: {max_abs}')

    for wlabel, ilabel, weights_src, inputs in combos:
        print('\n=== Comparison: weights=%s inputs=%s ===' % (wlabel, ilabel))
        if inputs is None:
            print('  Skipping: inputs not available for', ilabel)
            continue
        run_comparison_with_sources(weights_src, biases, inputs, simple=args.simple)


def run_comparison_with_sources(weights_addrs: List[List[int]], biases: List[int], inputs: List[int], simple: bool = False):
    """Run the same comparison loop as before but using provided weights and inputs.
    Prints per-neuron computed accumulator, final_int and q1.6, and compares to VHDL FC1 block."""
    print('Parsing FC1 output from debug file...')
    fc1_vhdl = parse_fc1_block(DEBUG_FILE)
    if not fc1_vhdl:
        print('No FC1_OUTPUT block found in debug log')

    # Choose neurons to inspect
    to_check = sorted([n for n, v in fc1_vhdl.items() if v != 0])[:20]
    if not to_check:
        to_check = [0, 24]

    rows = []
    for neuron in to_check:
        acc, final_int, q1_6 = compute_neuron(neuron, inputs, weights_addrs, biases)
        vhdl_raw = fc1_vhdl.get(neuron, 0)
        # VHDL prints are Q9.6 (signed 16-bit fixed point with 6 fractional bits).
        # Q9.6 and Q1.6 share the same fractional scaling (2^6), so the integer
        # representation is comparable. Convert by clipping to signed 8-bit range.
        vhdl_final_guess = max(-128, min(127, vhdl_raw))
        rows.append((neuron, q1_6, vhdl_final_guess, final_int - vhdl_final_guess, acc))

    if simple:
        # Compact table: neuron, computed_q1_6, vhdl_guess, diff
        print('neuron,computed_q1_6,vhdl_guess,diff')
        total_abs = 0
        for n, comp, vhdl_g, diff, acc in rows:
            print(f'{n:02d},{comp},{vhdl_g},{diff}')
            total_abs += abs(diff)
        avg = total_abs / len(rows) if rows else 0
        print(f'avg_abs_diff={avg:.3f} rows={len(rows)}')
    else:
        total_abs = 0
        for n, comp, vhdl_g, diff, acc in rows:
            print(f'Neuron {n + 1}: computed acc={acc} q1.6={comp} | vhdl_guess={vhdl_g} diff={diff}')
            total_abs += abs(diff)
        avg = total_abs / len(rows) if rows else 0
        print('\nAverage absolute difference: %.1f\n' % (avg,))
    # done


def run_comparison(reverse_bytes: bool):
    print('Loading weights...')
    weights = load_weights(reverse_bytes=reverse_bytes)
    print(f'Loaded {len(weights)} weight addresses (expected {N_INPUTS})')
    print('Loading biases...')
    biases = load_biases()
    print(f'Loaded {len(biases)} biases (expected {N_NEURONS})')

    print('Parsing Pool2 debug...')
    pool2 = parse_pool2(DEBUG_FILE)
    inputs = build_input_vector(pool2)
    print(f'Built input vector length {len(inputs)}')

    print('Parsing FC1 output from debug file...')
    fc1_vhdl = parse_fc1_block(DEBUG_FILE)
    if not fc1_vhdl:
        print('No FC1_OUTPUT block found in debug log')

    # Choose neurons to inspect (default: those VHDL printed non-zero)
    to_check = sorted([n for n, v in fc1_vhdl.items() if v != 0])[:10]
    if not to_check:
        to_check = [0, 24]

    print('\nComparing neurons:')
    total_abs_diff = 0
    for n in to_check:
        acc_q212, final_int, q1_6 = compute_neuron(n, inputs, weights, biases)
        vhdl_val = fc1_vhdl.get(n)
        print(f'Neuron {n}: computed acc={acc_q212} final_int={final_int} q1.6={q1_6} | vhdl_raw={vhdl_val}')
        if vhdl_val is not None:
            # Provide two comparisons: accumulator space and final_int space
            acc_diff = acc_q212 - (vhdl_val if abs(vhdl_val) > 127 else vhdl_val * Q_SCALE)
            final_guess = vhdl_val // Q_SCALE if abs(vhdl_val) > 127 else vhdl_val
            final_diff = abs(final_int - final_guess)
            total_abs_diff += final_diff
            print(f'  diff(acc - vhdl_acc_guess) = {acc_diff} | diff(final_int - vhdl_final_guess) = {final_int - final_guess}')
    
    avg_diff = total_abs_diff / len(to_check) if to_check else 0
    print(f'\nAverage absolute difference: {avg_diff:.1f}')


if __name__ == '__main__':
    main()
