#!/usr/bin/env python3
"""
Simple Debug Comparison Tool for CNN FPGA Implementation
Compares Python model outputs with VHDL simulation results
"""

import argparse
import csv
import numpy as np
import re
import os
from typing import List, Dict, Any, Optional

def parse_sim_output_file(filename: str, bits: int = 16) -> List[Dict[str, Any]]:
    """
    Parse Vivado simulation log and accept either:
      - machine-friendly lines like: SIM_OUT layer=layer0 r=0 c=1 filter=0 raw=0xffea scale=4096
      - or the existing human lines: MODULAR_OUTPUT: [r,c] followed by lines 'Filter_n: value'

    Returns a list of outputs: { 'row': int, 'col': int, 'filters': {idx: raw_int}, 'raw_lines': [...] }
    """
    outputs: List[Dict[str, Any]] = []

    # regexes
    sim_out_re = re.compile(r'^SIM_OUT\s+(.*)$')
    keyval_re = re.compile(r'(\w+)=([^\s]+)')
    modular_re = re.compile(r'^MODULAR_OUTPUT:\s*\[(\d+),(\d+)\]')
    cnn_re = re.compile(r'^(?:CNN_OUTPUT|MODULAR_OUTPUT):\s*\[(\d+),(\d+)\]')
    # NEW: Intermediate layer patterns
    layer0_re = re.compile(r'^LAYER0_CONV1_OUTPUT:\s*\[(\d+),(\d+)\]')
    layer1_re = re.compile(r'^LAYER1_POOL1_OUTPUT:\s*\[(\d+),(\d+)\]')
    layer2_re = re.compile(r'^LAYER2_CONV2_OUTPUT:\s*\[(\d+),(\d+)\]')
    # Generic pattern to catch other layer debug tags e.g. LAYER3_POOL2_OUTPUT
    generic_layer_re = re.compile(r'^LAYER(\d+)[A-Z0-9_]*_OUTPUT:\s*\[(\d+),(\d+)\]')
    filter_re1 = re.compile(r'^Filter[_ ]?(\d+):\s*([0-9A-Fa-fx\-]+)')
    filter_re2 = re.compile(r'^Filter\s+(\d+)\s*:\s*([0-9A-Fa-fx\-]+)')
    # FC output blocks
    fc1_re = re.compile(r'^FC1_OUTPUT:\s*$')
    fc2_re = re.compile(r'^FC2_OUTPUT:\s*$')
    neuron_re = re.compile(r'^(?:Neuron[_ ]?(\d+)|\s+Neuron[_ ]?(\d+))\s*:\s*([0-9A-Fa-fx\-]+)')
    class_re = re.compile(r'^(?:Class[_ ]?(\d+)|\s+Class[_ ]?(\d+))\s*:\s*([0-9A-Fa-fx\-]+)')
    # New TB format: Filter_<i>_hex: 0x..  dec: N
    filter_hex_re = re.compile(r'^Filter[_ ]?(\d+)_hex:\s*(0x[0-9A-Fa-f]+)')
    filter_hex_dec_re = re.compile(r'^Filter[_ ]?(\d+)_hex:.*dec:\s*([0-9]+)')

    current = None
    try:
        with open(filename, 'r') as f:
            for raw in f:
                line = raw.strip()
                if not line:
                    continue

                # Machine-friendly SIM_OUT
                m = sim_out_re.match(line)
                if m:
                    kvs = dict(keyval_re.findall(m.group(1)))
                    try:
                        r = int(kvs.get('r', kvs.get('row', 0)))
                        c = int(kvs.get('c', kvs.get('col', 0)))
                    except ValueError:
                        # ignore malformed
                        continue

                    entry = {'row': r, 'col': c, 'filters': {}, 'raw_lines': [line]}
                    # if filter provided as filter=idx:value pairs
                    if 'filter' in kvs and ':' in kvs['filter']:
                        fparts = kvs['filter'].split(':')
                        entry['filters'][int(fparts[0])] = parse_int(fparts[1])

                    # if raw and filter idx present
                    if 'raw' in kvs and 'filter_idx' in kvs:
                        entry['filters'][int(kvs['filter_idx'])] = parse_int(kvs['raw'])

                    outputs.append(entry)
                    current = entry
                    continue

                # Human-readable MODULAR_OUTPUT or CNN_OUTPUT or intermediate layers
                layer_type = None
                m2 = cnn_re.match(line)
                if m2:
                    layer_type = 'final'
                if not m2:
                    m2 = layer0_re.match(line)
                    if m2:
                        layer_type = 'layer0'
                if not m2:
                    m2 = layer1_re.match(line)
                    if m2:
                        layer_type = 'layer1'
                if not m2:
                    m2 = layer2_re.match(line)
                    if m2:
                        layer_type = 'layer2'
                if m2:
                    r, c = int(m2.group(1)), int(m2.group(2))
                    current = {'row': r, 'col': c, 'filters': {}, 'layer': layer_type, 'raw_lines': [line]}
                    outputs.append(current)
                    continue

                # Filter lines following MODULAR_OUTPUT (support multiple formats)
                if current is not None:
                    # New hex format: prefer hex parsing (8-bit values)
                    m_hex = filter_hex_re.match(line)
                    if m_hex:
                        idx = int(m_hex.group(1))
                        hex_str = m_hex.group(2)
                        # Interpret as 8-bit two's complement
                        # Use provided bit-width for two's complement interpretation
                        current['filters'][idx] = parse_int(hex_str, bits=bits)
                        current['raw_lines'].append(line)
                        continue

                    # If line contains hex but also 'dec: N', prefer hex; fallback to dec if needed
                    m_hexdec = filter_hex_dec_re.match(line)
                    if m_hexdec:
                        idx = int(m_hexdec.group(1))
                        dec_str = m_hexdec.group(2)
                        # dec in TB is unsigned decimal; convert to signed 8-bit
                        current['filters'][idx] = parse_int(dec_str, bits=bits)
                        current['raw_lines'].append(line)
                        continue

                    # Backwards-compatible formats
                    m3 = filter_re1.match(line) or filter_re2.match(line)
                    if m3:
                        idx = int(m3.group(1))
                        raw_str = m3.group(2)
                        current['filters'][idx] = parse_int(raw_str, bits=bits)
                        current['raw_lines'].append(line)
                        continue

                    # FC1 / FC2 human-readable blocks
                    m_fc1 = fc1_re.match(line)
                    if m_fc1:
                        # Start an FC1 block (dense 64 neurons)
                        current = {'row': None, 'col': None, 'filters': {}, 'layer': 'fc1', 'raw_lines': [line]}
                        outputs.append(current)
                        continue
                    m_fc2 = fc2_re.match(line)
                    if m_fc2:
                        # Start an FC2 block (dense 10 classes)
                        current = {'row': None, 'col': None, 'filters': {}, 'layer': 'fc2', 'raw_lines': [line]}
                        outputs.append(current)
                        continue

                    # Neuron lines (for FC1)
                    m_neuron = neuron_re.match(line)
                    if m_neuron:
                        idx = int(m_neuron.group(1) or m_neuron.group(2))
                        val = m_neuron.group(3)
                        current['filters'][idx] = parse_int(val, bits=bits)
                        current['raw_lines'].append(line)
                        continue

                    # Class lines (for FC2)
                    m_class = class_re.match(line)
                    if m_class:
                        idx = int(m_class.group(1) or m_class.group(2))
                        val = m_class.group(3)
                        current['filters'][idx] = parse_int(val, bits=bits)
                        current['raw_lines'].append(line)
                        continue

    except FileNotFoundError:
        print(f"Vivado log file {filename} not found.")
        return []

    return outputs

def parse_vivado_log_file(filename: str, bits: int = 16) -> Dict[str, Any]:
    """
    Backwards-compatible parser wrapper. Returns dict with 'inputs' and 'outputs'.
    """
    outputs = parse_sim_output_file(filename, bits=bits)
    return {'inputs': [], 'outputs': outputs}

def load_python_data(filename: str = "model/intermediate_values.npz"):
    """Load Python model intermediate values and return the full NPZ archive.

    The caller may select a specific layer by name. Prints available keys for convenience.
    """
    try:
        data = np.load(filename)
        keys = list(data.keys())
        print(f"Loaded Python data with keys: {keys}")
        return data
    except FileNotFoundError:
        print(f"Python data not found. Run CNN.py first.")
        return None


def generate_intermediate_from_test_image(test_image_npz: str, out_npz: str = "model/intermediate_values.npz"):
    """Generate a minimal intermediate_values.npz from an exported test image NPZ.

    The exported test image NPZ is expected to have keys: 'image' (28x28 uint8),
    'category' and 'category_idx'. This function will create synthetic intermediate
    layer outputs by running the same deterministic pre-processing used by
    model/CNN.py but it will not run a TF model; instead it will prepare the
    input array and save placeholders for the layer outputs so the comparison
    script can operate on the provided test image.
    """
    try:
        d = np.load(test_image_npz)
    except FileNotFoundError:
        print(f"Test image NPZ '{test_image_npz}' not found.")
        return None

    if 'image' not in d:
        print(f"Test image NPZ '{test_image_npz}' does not contain 'image' key.")
        return None

    image = d['image']
    # Ensure shape 28x28
    if image.shape != (28, 28):
        try:
            image = image.reshape(28, 28)
        except Exception:
            print("Provided image cannot be reshaped to 28x28")
            return None

    # Create the same batched shape used by CNN.py
    sample_input = np.expand_dims(np.expand_dims(image.astype(np.float32), 0), -1)

    # Try to run the Keras SavedModel if available so we get real intermediate values
    intermediate_data = {}
    tf_available = False
    try:
        import tensorflow as tf
        tf_available = True
    except Exception:
        tf_available = False

    if tf_available:
        # Attempt to load a saved model from model/saved_model
        model_path = os.path.join('model', 'saved_model')
        model = None
        try:
            if os.path.isdir(model_path):
                model = tf.keras.models.load_model(model_path)
                print(f"Loaded SavedModel from: {model_path}")
        except Exception as e:
            print(f"Could not load SavedModel from {model_path}: {e}")
            model = None

        if model is not None:
            # Build an intermediate model that exposes every layer's output
            try:
                layer_outputs = [layer.output for layer in model.layers]
                intermediate_model = tf.keras.Model(inputs=model.input, outputs=layer_outputs)
                preds = intermediate_model.predict(sample_input)

                for i, out in enumerate(preds):
                    # out is batched; drop batch dimension
                    arr = out[0]
                    intermediate_data[f"layer_{i}_output"] = arr

                    # For Conv2D layers, also expose per-filter 2D maps similar to CNN.py
                    if arr.ndim == 3:
                        for fidx in range(arr.shape[-1]):
                            intermediate_data[f"layer_{i}_filter_{fidx}"] = arr[:, :, fidx]

                # Also record the input image
                intermediate_data['input_image'] = image.astype(np.uint8)

                # Save and return
                os.makedirs(os.path.dirname(out_npz), exist_ok=True)
                np.savez(out_npz, **intermediate_data)
                print(f"✓ Captured and saved intermediate values to: {out_npz}")
                return np.load(out_npz)
            except Exception as e:
                print(f"Failed to run intermediate model prediction: {e}")

    # Fallback: create placeholders when TF or SavedModel are not available
    # Layer shapes inferred from the model architecture in CNN.py:
    # layer 0 conv: output shape (26,26,8)
    intermediate_data['layer_0_output'] = np.zeros((26, 26, 8), dtype=np.float32)
    # layer 1 pool: (13,13,8)
    intermediate_data['layer_1_output'] = np.zeros((13, 13, 8), dtype=np.float32)
    # layer 2 conv: (11,11,16)
    intermediate_data['layer_2_output'] = np.zeros((11, 11, 16), dtype=np.float32)
    # layer 3 pool (pool2): (5,5,16)
    intermediate_data['layer_3_output'] = np.zeros((5, 5, 16), dtype=np.float32)
    # layer 4 flatten: (400,)
    intermediate_data['layer_4_output'] = np.zeros((400,), dtype=np.float32)
    # layer 5 fc1: (64,)
    intermediate_data['layer_5_output'] = np.zeros((64,), dtype=np.float32)
    # layer 6 fc2: (num_classes,) - if category_idx present assume categories length unknown; default 10
    num_classes = int(d.get('category_idx', 0)) + 1 if 'category_idx' in d else 10
    num_classes = max(num_classes, 10)
    intermediate_data['layer_6_output'] = np.zeros((num_classes,), dtype=np.float32)

    # Also save the input image as 'input_image' for convenience
    intermediate_data['input_image'] = image.astype(np.uint8)

    # Save to NPZ
    os.makedirs(os.path.dirname(out_npz), exist_ok=True)
    np.savez(out_npz, **intermediate_data)
    print(f"✓ Generated placeholder intermediate values at: {out_npz}")
    return np.load(out_npz)


def pick_python_layer(npz_archive: np.lib.npyio.NpzFile, layer_name: Optional[str] = None):
    """Pick a layer array from the NPZ archive.

    If layer_name is provided and exists, return it. Otherwise, attempt to find
    common naming patterns (layer_X_output, layer_X_filter_Y or similar) and return
    a sensible default (first conv/pool output found).
    Returns (array, key_name) or (None, None) on failure.
    """
    if npz_archive is None:
        return None, None

    keys = list(npz_archive.keys())
    if layer_name:
        if layer_name in npz_archive:
            return npz_archive[layer_name], layer_name
        # allow numeric layer index like 'layer_2' mapping to 'layer_2_output'
        alt = f"layer_{layer_name}_output"
        if alt in npz_archive:
            return npz_archive[alt], alt
        print(f"Requested layer '{layer_name}' not found. Available keys: {keys}")
        return None, None

    # No layer requested: find the first multi-dimensional array suitable for conv/pool
    # Prefer 'layer_#_output' patterns
    for k in keys:
        if re.match(r"layer_\d+_output", k):
            return npz_archive[k], k

    # Fallback: return the first array
    if keys:
        return npz_archive[keys[0]], keys[0]

    return None, None

def get_weight_scale_factor():
    """Get the actual weight scale factor used in CNN.py (Q1.6 default)."""
    return 64


def parse_int(s: str, bits: Optional[int] = 16) -> int:
    """Parse a decimal or hex (0x..) signed integer string into Python int.
    bits: assumed bit width for two's complement conversion.
    """
    s = s.strip()
    try:
        if s.lower().startswith('0x'):
            val = int(s, 16)
        else:
            val = int(s, 0)
    except ValueError:
        # fallback: strip non-digits
        digits = re.sub(r'[^0-9a-fA-F\-xX]', '', s)
        if digits.lower().startswith('0x'):
            val = int(digits, 16)
        else:
            val = int(digits)

    # convert from unsigned representation to signed
    if val >= (1 << (bits-1)):
        val = val - (1 << bits)
    return val

def fixed_to_float(vhdl_value: int, scale_factor: int = 4096, bits: int = 16) -> float:
    """Convert a signed fixed integer (two's complement) to float by scale factor.
    bits is the bit-width of vhdl_value (default 16)."""
    # ensure signed conversion already done by parse_int; but guard anyway
    if vhdl_value >= (1 << (bits-1)):
        v = vhdl_value - (1 << bits)
    else:
        v = vhdl_value
    return v / float(scale_factor)

def find_best_scale_factor(python_data, vhdl_outputs):
    """Find the best scale factor by trying different values."""
    if not vhdl_outputs or python_data is None:
        return 256
    
    scale_factors = [64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384]
    best_error = float('inf')
    best_scale = 256
    
    print("\n=== Finding Best Scale Factor ===")
    
    # Test with first few outputs
    test_outputs = vhdl_outputs[:3]
    
    for scale in scale_factors:
        total_error = 0
        count = 0
        
        for output in test_outputs:
            row, col = output['row'], output['col']
            if row < python_data.shape[0] and col < python_data.shape[1]:
                for filter_idx, vhdl_raw in output['filters'].items():
                    if filter_idx < python_data.shape[2]:
                        python_val = python_data[row, col, filter_idx]
                        vhdl_float = fixed_to_float(vhdl_raw, scale)
                        vhdl_relu = max(0.0, vhdl_float)
                        error = abs(python_val - vhdl_relu)
                        total_error += error
                        count += 1
        
        if count > 0:
            avg_error = total_error / count
            print(f"Scale {scale:5d}: Average error = {avg_error:.6f}")
            if avg_error < best_error:
                best_error = avg_error
                best_scale = scale
    
    print(f"Best scale factor: {best_scale} (error: {best_error:.6f})")
    return best_scale

def analyze_scaling(output_scale_factor=64):
    """Analyze the scaling relationship between Q1.6 weights and outputs."""
    # Condensed scaling summary
    print("\n=== Scaling Summary ===")
    if output_scale_factor == 64:
        print("Outputs expected in Q1.6 (8-bit signed, scale=64) post-ReLU.")
    elif output_scale_factor == 1:
        print("Outputs expected as raw integers (no scaling).")
    else:
        print(f"Outputs expected as {output_scale_factor}-scale signed integers (bits vary).")
    print("(Use --vhdl_scale and --vhdl_bits to adjust parser expectations.)")

def compare_outputs(python_data, vhdl_outputs, output_scale_factor=64, vhdl_bits=8, layer_key=None, vhdl_layer=None, display_limit: int = 80):
    """Compare Python and VHDL outputs at all positions.

    Supports 3D conv/pool outputs (H x W x C) and 1D dense outputs.
    If python_data is an NPZ archive, the caller must pass the selected layer array.
    """
    if python_data is None or vhdl_outputs is None:
        print("❌ Missing data for comparison")
        return

    # python_data may be an np.ndarray or an npz archive entry; ensure it's ndarray
    if hasattr(python_data, 'shape'):
        py = python_data
    else:
        print("Invalid python data provided to compare_outputs")
        return

    # Detect if Python data is FC layer (1D output)
    is_fc_layer = (py.ndim == 1)
    
    # Filter VHDL outputs either by provided explicit vhdl_layer or inferred from python layer_key
    layer_type_map = {
        'layer_0_output': 'layer0',
        'layer_1_output': 'layer1',
        'layer_2_output': 'layer2',
        # Pool2 (Python layer_3) is emitted as LAYER3_POOL2_OUTPUT in the TB
        'layer_3_output': 'layer3',
        'layer_4_output': 'flatten',
        'layer_5_output': 'fc1',  # FC1 (Dense 64)
        'layer_6_output': 'fc2',  # FC2 (Dense 10)
        'cnn_output': 'final'
    }

    if vhdl_layer:
        filtered_outputs = [o for o in vhdl_outputs if o.get('layer') == vhdl_layer]
        print(f"🔍 Filtering VHDL outputs for explicit vhdl_layer='{vhdl_layer}': {len(vhdl_outputs)} → {len(filtered_outputs)} outputs")
        vhdl_outputs = filtered_outputs
    elif layer_key and layer_key in layer_type_map:
        expected_layer_type = layer_type_map[layer_key]
        filtered_outputs = [o for o in vhdl_outputs if o.get('layer') == expected_layer_type]
        print(f"🔍 Filtering for layer '{layer_key}' (type='{expected_layer_type}'): {len(vhdl_outputs)} → {len(filtered_outputs)} outputs")
        vhdl_outputs = filtered_outputs
    
    # For FC layers, use only the LAST block (final output after all inputs processed)
    if is_fc_layer and len(vhdl_outputs) > 1:
        print(f"🔍 FC layer detected: using last of {len(vhdl_outputs)} FC blocks")
        vhdl_outputs = [vhdl_outputs[-1]]

    print(f"\n=== Comparison Results ===")
    print(f"Python data shape: {py.shape}")
    print(f"VHDL outputs: {len(vhdl_outputs)} positions")
    print(f"Weight format: Q1.6 (8-bit signed, scale = {get_weight_scale_factor()})")

    if output_scale_factor == 64 and vhdl_bits == 8:
        format_desc = "Q1.6 (8-bit signed, scale = 64)"
    elif output_scale_factor == 1:
        format_desc = "Raw integer"
    else:
        format_desc = f"{vhdl_bits}-bit signed (scale = {output_scale_factor})"
    print(f"Output format: {format_desc}")

    total_error = 0.0
    total_abs_error = 0.0
    valid_comparisons = 0
    max_error = 0.0
    max_error_pos = None
    filter_errors = {}

    # Helper to index Python data depending on its dimensionality
    def get_python_value(pyarr, r, c, fidx):
        # If 1D (FC/dense layer): ignore r,c, use filter_idx as neuron index
        if pyarr.ndim == 1:
            if 0 <= fidx < pyarr.shape[0]:
                return float(pyarr[fidx])
            return 0.0
        # If 3D (H,W,C)
        if pyarr.ndim == 3:
            return float(pyarr[r, c, fidx])
        # If 2D (H,W) and fidx==0
        if pyarr.ndim == 2:
            # Only valid when comparing a single-channel output
            if fidx == 0:
                return float(pyarr[r, c])
            return 0.0
        # If 4D (batch,H,W,C) choose first batch element
        if pyarr.ndim == 4:
            return float(pyarr[0, r, c, fidx])
        return 0.0

    # Display header
    if is_fc_layer:
        print("\nNeuron   | Python   | VHDL(float) | VHDL(raw) | Error    | Rel.Err")
        print("---------|----------|-------------|-----------|----------|--------")
    else:
        print("\nPosition | Filter | Python   | VHDL(float) | VHDL(raw) | Error    | Rel.Err")
        print("---------|--------|----------|-------------|-----------|----------|--------")

    # Show first N positions for quick debugging (non-mutating display)
    display_count = 0
    for output in vhdl_outputs[:display_limit]:
        row, col = output['row'], output['col']
        for filter_idx, vhdl_raw in output['filters'].items():
            # Skip filters outside python shape
            if py.ndim == 1 and filter_idx >= py.shape[0]:
                continue
            if py.ndim >= 3 and filter_idx >= py.shape[2]:
                continue
            python_val = get_python_value(py, row, col, filter_idx)
            vhdl_float = fixed_to_float(vhdl_raw, scale_factor=output_scale_factor, bits=vhdl_bits)
            vhdl_relu = max(0.0, vhdl_float)
            error = abs(python_val - vhdl_relu)
            rel_error = (error / max(abs(python_val), 0.001)) * 100

            if display_count < display_limit:
                if is_fc_layer:
                    print(f"   {filter_idx:3d}   | {python_val:8.5f} | {vhdl_relu:11.5f} | {vhdl_raw:9d} | {error:8.5f} | {rel_error:6.1f}%")
                else:
                    print(f"[{row:2d},{col:2d}] |   {filter_idx}    | {python_val:8.5f} | {vhdl_relu:11.5f} | {vhdl_raw:9d} | {error:8.5f} | {rel_error:6.1f}%")
                display_count += 1

    # Now compute aggregate statistics across all reported VHDL outputs
    for output in vhdl_outputs:
        row, col = output['row'], output['col']
        for filter_idx, vhdl_raw in output['filters'].items():
            if py.ndim == 1 and filter_idx >= py.shape[0]:
                continue
            if py.ndim >= 3 and filter_idx >= py.shape[2]:
                continue
            python_val = get_python_value(py, row, col, filter_idx)
            vhdl_float = fixed_to_float(vhdl_raw, scale_factor=output_scale_factor, bits=vhdl_bits)
            vhdl_relu = max(0.0, vhdl_float)
            error = abs(python_val - vhdl_relu)

            # We already counted the first displayed comparisons; continue counting all
            total_error += error
            total_abs_error += abs(error)
            valid_comparisons += 1

            if error > max_error:
                max_error = error
                max_error_pos = (row, col, filter_idx)

            if filter_idx not in filter_errors:
                filter_errors[filter_idx] = {'count': 0, 'total_error': 0.0, 'zero_count': 0}
            filter_errors[filter_idx]['count'] += 1
            filter_errors[filter_idx]['total_error'] += error
            if vhdl_raw == 0:
                filter_errors[filter_idx]['zero_count'] += 1

    if valid_comparisons > 0:
        avg_error = total_error / valid_comparisons
        avg_abs_error = total_abs_error / valid_comparisons

        print(f"\n{'='*70}")
        print(f"OVERALL STATISTICS ({valid_comparisons} comparisons)")
        print(f"{'='*70}")
        print(f"Average Error:     {avg_error:.6f}")
        print(f"Average Abs Error: {avg_abs_error:.6f}")
        print(f"Max Error:         {max_error:.6f} at position {max_error_pos}")

        if is_fc_layer:
            print(f"Per-Neuron Analysis:")
            print(f"Neuron | Avg Error | Zero Count | Total Samples")
            print(f"-------|-----------|------------|---------------")
        else:
            print(f"Per-Filter Analysis:")
            print(f"Filter | Avg Error | Zero Count | Total Samples")
            print(f"-------|-----------|------------|---------------")
        for filt_idx in sorted(filter_errors.keys()):
            stats = filter_errors[filt_idx]
            avg_f_error = stats['total_error'] / stats['count'] if stats['count'] > 0 else 0
            zero_pct = (stats['zero_count'] / stats['count'] * 100) if stats['count'] > 0 else 0
            print(f"  {filt_idx:3d}  | {avg_f_error:9.6f} | {stats['zero_count']:4d}/{stats['count']:4d} | {zero_pct:5.1f}% zeros")

        print(f"\nQuantization Summary:")
        print(f"  - Weights: Q1.6 format (8-bit signed, scale = 64)")
        print(f"  - Outputs: {format_desc}")
        if output_scale_factor == 64:
            print(f"  - Range: weights ±2.0, outputs ±2.0 (Q1.6)")
        else:
            print(f"  - Range: weights ±2.0, outputs ±{(1 << (vhdl_bits-1))/output_scale_factor:.1f}")

    return avg_error if valid_comparisons > 0 else None


def validate_fc2_argmax(npz_archive, vhdl_outputs, vhdl_bits=16, scale=64):
    """Validate FC2 (final classification) against Python layer_6_output.
    Looks for an 'fc2' block in vhdl_outputs and compares argmax index to Python argmax.
    """
    # Find FC2 block(s)
    fc2_blocks = [o for o in vhdl_outputs if o.get('layer') == 'fc2']
    if not fc2_blocks:
        print("No FC2 outputs found in VHDL debug log to validate.")
        return None

    # Use the last FC2 block (most recent)
    fc2 = fc2_blocks[-1]
    # Find argmax from FC2: pick index with largest signed value
    if not fc2['filters']:
        print("FC2 block has no class scores.")
        return None

    # Convert raw to float with scale
    scores = {idx: fixed_to_float(raw, scale_factor=scale, bits=vhdl_bits) for idx, raw in fc2['filters'].items()}
    # Compute argmax
    vhdl_argmax = max(scores.items(), key=lambda kv: kv[1])[0]
    print(f"VHDL FC2 argmax: {vhdl_argmax} (score={scores[vhdl_argmax]:.6f})")

    # Load Python final layer if present
    if npz_archive is None:
        print("No Python NPZ archive available for comparison.")
        return None
    if 'layer_6_output' not in npz_archive:
        print("Python final layer 'layer_6_output' not found in NPZ archive.")
        return None

    py_final = npz_archive['layer_6_output']
    # Python final likely shape (10,) or (1,10)
    if py_final.ndim == 2:
        py_final = py_final[0]
    py_argmax = int(np.argmax(py_final))
    print(f"Python argmax: {py_argmax} (value={py_final[py_argmax]:.6f})")

    match = (py_argmax == vhdl_argmax)
    print("Validation result: " + ("MATCH" if match else "MISMATCH"))
    return match

def main():
    """Simple comparison between Python and VHDL outputs."""
    print("Simple CNN Debug Comparison")
    print("=" * 30)
    
    # Load data
    parser = argparse.ArgumentParser(description='Compare Python model outputs with VHDL sim outputs')
    parser.add_argument('--vivado', default='vivado.log', help='Vivado simulation log file (or SIM_OUT formatted file)')
    parser.add_argument('--npz', default='model/intermediate_values.npz', help='Python intermediate NPZ file')
    parser.add_argument('--test_image', default=None, help='Optional exported test image NPZ; if provided, generate intermediate_values.npz from it')
    parser.add_argument('--vhdl_scale', type=int, default=64, help='VHDL output scale (64 for Q1.6, default=64)')
    parser.add_argument('--vhdl_bits', type=int, default=8, help='VHDL output integer bit-width (8 for Q1.6, 16 for raw MAC)')
    parser.add_argument('--vhdl_layer', type=str, default=None, help="VHDL layer type to filter (e.g. 'final','layer0','layer1','layer2'). If omitted, script will map from the Python layer name.)")
    parser.add_argument('--layer', type=str, default=None, help='Python layer key to compare (e.g. layer_0_output). If omitted, first available layer is used.')
    parser.add_argument('--show', type=int, default=80, help='How many VHDL positions to print for debugging (default 80)')
    args = parser.parse_args()

    # If user provided a test image, generate an intermediate_values.npz from it
    if args.test_image:
        print(f"Generating intermediate values from test image: {args.test_image}")
        gen = generate_intermediate_from_test_image(args.test_image, out_npz=args.npz)
        if gen is None:
            print("Failed to generate intermediate values from test image. Aborting.")
            return

    npz_archive = load_python_data(args.npz)
    parsed = parse_vivado_log_file(args.vivado, bits=args.vhdl_bits)
    vhdl_outputs = parsed.get('outputs', [])

    if npz_archive is None:
        print("❌ No Python data. Run: python model/CNN.py")
        return

    # Pick layer to compare
    py_layer_arr, layer_key = pick_python_layer(npz_archive, layer_name=args.layer)
    if py_layer_arr is None:
        print("❌ Could not select a Python layer for comparison. Aborting.")
        return
    print(f"Comparing layer: {layer_key}")
    
    if not vhdl_outputs:
        print("❌ No VHDL data. Run VHDL simulation first.")
        return
    
    # Analyze scaling
    analyze_scaling(args.vhdl_scale)

    # Compare using provided VHDL scale (default Q1.6 -> 64)
    # If user provided an explicit VHDL layer type, pass it through to the comparator
    # Use args.show to control how many VHDL positions to print for debugging
    avg_error = compare_outputs(py_layer_arr, vhdl_outputs, output_scale_factor=args.vhdl_scale, vhdl_bits=args.vhdl_bits, layer_key=layer_key, vhdl_layer=args.vhdl_layer, display_limit=args.show)
    
    if avg_error is not None:
        if avg_error < 0.01:
            print(f"\n[EXCELLENT] Average error: {avg_error:.6f}")
            print("   Your VHDL implementation matches the Python model very well.")
        elif avg_error < 0.05:
            print(f"\n[GOOD] Average error: {avg_error:.6f}")
            print("   Your VHDL implementation matches the Python model well.")
        elif avg_error < 0.2:
            print(f"\n[MODERATE] Average error: {avg_error:.6f}")
            print("   Consider investigating systematic offsets or scaling issues.")
        else:
            print(f"\n[POOR] Average error: {avg_error:.6f}")
            print("   Significant discrepancies detected. Check implementation carefully.")
    
    print("\n=== Verification Summary ===")
    if args.vhdl_scale == 64 and args.vhdl_bits == 8:
        print("Configuration: VHDL outputs are Q1.6 format (post-ReLU)")
        print("This is the expected format for the modular CNN implementation")
    elif args.vhdl_scale == 1:
        print("Configuration: VHDL outputs are raw integers (no scaling)")
        print("  Use --vhdl_scale 64 if values are Q1.6 format")
    else:
        print(f"Configuration: VHDL scale={args.vhdl_scale}, bits={args.vhdl_bits}")
        print("  Expected: --vhdl_scale 64 --vhdl_bits 8 for Q1.6 format")
    
    # End: no troubleshooting noise by default. The user can inspect per-filter stats and raw_lines in output files.
    # Additionally, attempt to validate FC2 (final classification) if present in the VHDL debug output
    try:
        fc2_match = validate_fc2_argmax(npz_archive, vhdl_outputs, vhdl_bits=args.vhdl_bits, scale=args.vhdl_scale)
        if fc2_match is not None:
            if fc2_match:
                print("\nFC2 argmax matches Python final class.")
            else:
                print("\nFC2 argmax does NOT match Python final class.")
    except Exception as e:
        print(f"FC2 validation raised an exception: {e}")

if __name__ == "__main__":
    main()