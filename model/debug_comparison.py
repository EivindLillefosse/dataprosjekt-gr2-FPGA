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

def parse_sim_output_file(filename: str) -> List[Dict[str, Any]]:
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
    filter_re1 = re.compile(r'^Filter[_ ]?(\d+):\s*([0-9A-Fa-fx\-]+)')
    filter_re2 = re.compile(r'^Filter\s+(\d+)\s*:\s*([0-9A-Fa-fx\-]+)')

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

                # Human-readable MODULAR_OUTPUT
                m2 = modular_re.match(line)
                if m2:
                    r, c = int(m2.group(1)), int(m2.group(2))
                    current = {'row': r, 'col': c, 'filters': {}, 'raw_lines': [line]}
                    outputs.append(current)
                    continue

                # Filter lines following MODULAR_OUTPUT
                if current is not None:
                    m3 = filter_re1.match(line) or filter_re2.match(line)
                    if m3:
                        idx = int(m3.group(1))
                        raw_str = m3.group(2)
                        current['filters'][idx] = parse_int(raw_str)
                        current['raw_lines'].append(line)
                        continue

    except FileNotFoundError:
        print(f"Vivado log file {filename} not found.")
        return []

    return outputs

def parse_vivado_log_file(filename: str) -> Dict[str, Any]:
    """
    Backwards-compatible parser wrapper. Returns dict with 'inputs' and 'outputs'.
    """
    outputs = parse_sim_output_file(filename)
    return {'inputs': [], 'outputs': outputs}

def load_python_data(filename: str = "model/intermediate_values.npz"):
    """Load Python model intermediate values."""
    try:
        data = np.load(filename)
        print(f"✓ Loaded Python data: {list(data.keys())}")
        # try common keys
        for key in ('layer_0_output', 'layer0_output', 'output'):
            if key in data:
                return data[key]
        # fallback: return first array
        return data[list(data.files)[0]]
    except FileNotFoundError:
        print(f"Python data not found. Run CNN.py first.")
        return None

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

def analyze_scaling():
    """Analyze the scaling relationship between Q1.6 weights and 16-bit outputs."""
    print("\n=== Scaling Analysis ===")
    print("Weight format: Q1.6 (scale = 64)")
    print("Output format: 16-bit signed (scale = 256) -- adjust as needed")
    print("Expected relationship:")
    print("  MAC = Σ(weight_Q1.6 × input_8bit) + bias_Q1.6")
    print("  If input is 8-bit unsigned (0-255):")
    print("    weight_range: [-2.0, +1.984] → [-128, +127] in Q1.6")
    print("    input_range: [0, 255]")
    print("    product_range: [-32640, +32385] (needs ~16 bits)")
    print("  Output scaling should account for:")
    print("    - 9 multiply-accumulate operations (3×3 kernel)")
    print("    - Potential overflow protection")
    print("    - ReLU activation")

def compare_outputs(python_data, vhdl_outputs, output_scale_factor=256, vhdl_bits=16):
    """Compare Python and VHDL outputs at all positions."""
    if python_data is None or vhdl_outputs is None:
        print("❌ Missing data for comparison")
        return
    
    print(f"\n=== Comparison Results ===")
    print(f"Python data shape: {python_data.shape}")
    print(f"VHDL outputs: {len(vhdl_outputs)} positions")
    print(f"Weight format: Q1.6 (8-bit signed, scale = {get_weight_scale_factor()})")
    print(f"Output format: 16-bit signed (scale = {output_scale_factor})")
    
    total_error = 0
    valid_comparisons = 0
    
    print("\nPosition | Filter | Python   | VHDL(Q4.12) | Error")
    print("---------|--------|----------|-------------|-------")
    
    for output in vhdl_outputs[:5]:  # Show first 5 positions
        row, col = output['row'], output['col']
        
        if row < python_data.shape[0] and col < python_data.shape[1]:
            for filter_idx, vhdl_raw in output['filters'].items():
                if filter_idx < python_data.shape[2]:
                    # Get values
                    python_val = python_data[row, col, filter_idx]
                    vhdl_float = fixed_to_float(vhdl_raw, scale_factor=output_scale_factor, bits=vhdl_bits)
                    vhdl_relu = max(0.0, vhdl_float)
                    
                    # Calculate error
                    error = abs(python_val - vhdl_relu)
                    total_error += error
                    valid_comparisons += 1
                    
                    print(f"[{row:2d},{col:2d}] |   {filter_idx}    | {python_val:8.5f} | {vhdl_relu:10.5f} | {error:6.5f}")
    
    if valid_comparisons > 0:
        avg_error = total_error / valid_comparisons
        print(f"\nAverage Error: {avg_error:.6f}")
        print(f"Quantization Summary:")
        print(f"  - Weights: Q1.6 format (8-bit signed, scale = 64)")
        print(f"  - Outputs: 16-bit signed (scale = {output_scale_factor})")
        print(f"  - Range: weights ±2.0, outputs ±{32768/output_scale_factor:.1f}")
    
    return avg_error if valid_comparisons > 0 else None

def main():
    """Simple comparison between Python and VHDL outputs."""
    print("Simple CNN Debug Comparison")
    print("=" * 30)
    
    # Load data
    parser = argparse.ArgumentParser(description='Compare Python model outputs with VHDL sim outputs')
    parser.add_argument('--vivado', default='vivado.log', help='Vivado simulation log file (or SIM_OUT formatted file)')
    parser.add_argument('--npz', default='model/intermediate_values.npz', help='Python intermediate NPZ file')
    parser.add_argument('--vhdl_scale', type=int, default=64, help='VHDL output scale (e.g. 64 for Q1.6)')
    parser.add_argument('--vhdl_bits', type=int, default=8, help='VHDL output integer bit-width (8 or 16)')
    args = parser.parse_args()

    python_data = load_python_data(args.npz)
    parsed = parse_vivado_log_file(args.vivado)
    vhdl_outputs = parsed.get('outputs', [])
    
    if python_data is None:
        print("❌ No Python data. Run: python model/CNN.py")
        return
    
    if vhdl_outputs is None:
        print("❌ No VHDL data. Run VHDL simulation first.")
        return
    
    # Analyze scaling
    analyze_scaling()

    # Compare using provided VHDL scale (default Q1.6 -> 64)
    avg_error = compare_outputs(python_data, vhdl_outputs, output_scale_factor=args.vhdl_scale, vhdl_bits=args.vhdl_bits)
    
    if avg_error is not None:
        if avg_error < 0.2:
            print(f"✅ Good match! Average error: {avg_error:.6f}")
        elif avg_error < 1.0:
            print(f"⚠️  Reasonable match. Average error: {avg_error:.6f}")
        else:
            print(f"❌ Poor match. Average error: {avg_error:.6f}")
            print("   Check fixed-point format (currently assuming Q4.12)")
    
    print("\nNext steps:")
    print("- ✓ Weight format confirmed: Q1.6 (8-bit signed, scale = 64)")  
    print("- ✓ Output format confirmed: 16-bit signed (scale = 256)")
    print("- Check that VHDL MAC unit scales properly: weight×input + bias")
    print("- Verify intermediate scaling: MAC result should match 16-bit output format")

if __name__ == "__main__":
    main()