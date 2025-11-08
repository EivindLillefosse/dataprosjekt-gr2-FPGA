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
    filter_re1 = re.compile(r'^Filter[_ ]?(\d+):\s*([0-9A-Fa-fx\-]+)')
    filter_re2 = re.compile(r'^Filter\s+(\d+)\s*:\s*([0-9A-Fa-fx\-]+)')
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
        print(f"✓ Loaded Python data with keys: {keys}")
        return data
    except FileNotFoundError:
        print(f"Python data not found. Run CNN.py first.")
        return None


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

def compare_outputs(python_data, vhdl_outputs, output_scale_factor=64, vhdl_bits=8, layer_key=None, vhdl_layer=None):
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

    # Filter VHDL outputs either by provided explicit vhdl_layer or inferred from python layer_key
    layer_type_map = {
        'layer_0_output': 'layer0',
        'layer_1_output': 'layer1',
        'layer_2_output': 'layer2',
        'layer_3_output': 'final',
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
        # If 3D (H,W,C)
        if pyarr.ndim == 3:
            return float(pyarr[r, c, fidx])
        # If 2D (H,W) and fidx==0
        if pyarr.ndim == 2:
            # Only valid when comparing a single-channel output
            if fidx == 0:
                return float(pyarr[r, c])
            return 0.0
        # If 1D (dense)
        if pyarr.ndim == 1:
            # Dense output: ensure filter index is within bounds
            if 0 <= fidx < pyarr.shape[0]:
                return float(pyarr[fidx])
            # Out-of-range filter reported by VHDL; return 0.0 to allow comparison to continue
            return 0.0
        # If 4D (batch,H,W,C) choose first batch element
        if pyarr.ndim == 4:
            return float(pyarr[0, r, c, fidx])
        return 0.0

    # Display header
    print("\nPosition | Filter | Python   | VHDL(float) | VHDL(raw) | Error    | Rel.Err")
    print("---------|--------|----------|-------------|-----------|----------|--------")

    # Show first N positions for quick debugging
    for output in vhdl_outputs[:10]:
        row, col = output['row'], output['col']
        for filter_idx, vhdl_raw in output['filters'].items():
            # Skip filters outside python shape
            if py.ndim >= 3 and filter_idx >= py.shape[2]:
                continue
            python_val = get_python_value(py, row, col, filter_idx)
            vhdl_float = fixed_to_float(vhdl_raw, scale_factor=output_scale_factor, bits=vhdl_bits)
            vhdl_relu = max(0.0, vhdl_float)
            error = abs(python_val - vhdl_relu)
            rel_error = (error / max(abs(python_val), 0.001)) * 100

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

            if valid_comparisons <= 80:
                print(f"[{row:2d},{col:2d}] |   {filter_idx}    | {python_val:8.5f} | {vhdl_relu:11.5f} | {vhdl_raw:9d} | {error:8.5f} | {rel_error:6.1f}%")

    # Now compute aggregate statistics across all reported VHDL outputs
    for output in vhdl_outputs:
        row, col = output['row'], output['col']
        for filter_idx, vhdl_raw in output['filters'].items():
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

def main():
    """Simple comparison between Python and VHDL outputs."""
    print("Simple CNN Debug Comparison")
    print("=" * 30)
    
    # Load data
    parser = argparse.ArgumentParser(description='Compare Python model outputs with VHDL sim outputs')
    parser.add_argument('--vivado', default='vivado.log', help='Vivado simulation log file (or SIM_OUT formatted file)')
    parser.add_argument('--npz', default='model/intermediate_values.npz', help='Python intermediate NPZ file')
    parser.add_argument('--vhdl_scale', type=int, default=64, help='VHDL output scale (64 for Q1.6, default=64)')
    parser.add_argument('--vhdl_bits', type=int, default=8, help='VHDL output integer bit-width (8 for Q1.6, 16 for raw MAC)')
    parser.add_argument('--vhdl_layer', type=str, default=None, help="VHDL layer type to filter (e.g. 'final','layer0','layer1','layer2'). If omitted, script will map from the Python layer name.)")
    parser.add_argument('--layer', type=str, default=None, help='Python layer key to compare (e.g. layer_0_output). If omitted, first available layer is used.')
    args = parser.parse_args()

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
    avg_error = compare_outputs(py_layer_arr, vhdl_outputs, output_scale_factor=args.vhdl_scale, vhdl_bits=args.vhdl_bits, layer_key=layer_key, vhdl_layer=args.vhdl_layer)
    
    if avg_error is not None:
        if avg_error < 0.01:
            print(f"\n✅ Excellent match! Average error: {avg_error:.6f}")
            print("   Your VHDL implementation matches the Python model very well.")
        elif avg_error < 0.05:
            print(f"\n✅ Good match! Average error: {avg_error:.6f}")
            print("   Your VHDL implementation matches the Python model well.")
        elif avg_error < 0.2:
            print(f"\n⚠️  Moderate match. Average error: {avg_error:.6f}")
            print("   Consider investigating systematic offsets or scaling issues.")
        else:
            print(f"\n❌ Poor match. Average error: {avg_error:.6f}")
            print("   Significant discrepancies detected. Check implementation carefully.")
    
    print("\n=== Verification Summary ===")
    if args.vhdl_scale == 64 and args.vhdl_bits == 8:
        print("✓ Configuration: VHDL outputs are Q1.6 format (post-ReLU)")
        print("✓ This is the expected format for the modular CNN implementation")
    elif args.vhdl_scale == 1:
        print("⚠ Configuration: VHDL outputs are raw integers (no scaling)")
        print("  Use --vhdl_scale 64 if values are Q1.6 format")
    else:
        print(f"⚠ Configuration: VHDL scale={args.vhdl_scale}, bits={args.vhdl_bits}")
        print("  Expected: --vhdl_scale 64 --vhdl_bits 8 for Q1.6 format")
    
    # End: no troubleshooting noise by default. The user can inspect per-filter stats and raw_lines in output files.

if __name__ == "__main__":
    main()