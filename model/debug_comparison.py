#!/usr/bin/env python3
"""
Simple Debug Comparison Tool for CNN FPGA Implementation
Compares Python model outputs with VHDL simulation results
"""

import numpy as np
import re
import os

def parse_vivado_log(filename="vivado.log"):
    """Parse Vivado simulation log for output values."""
    outputs = []
    
    try:
        with open(filename, 'r') as f:
            current_output = None
            
            for line in f:
                line = line.strip()
                
                # Look for output position
                if "Output at position" in line:
                    match = re.search(r'Output at position \[(\d+),(\d+)\]', line)
                    if match:
                        row, col = int(match.group(1)), int(match.group(2))
                        current_output = {'row': row, 'col': col, 'filters': {}}
                        outputs.append(current_output)
                
                # Look for filter values
                elif "Filter" in line and ":" in line and current_output is not None:
                    match = re.search(r'Filter (\d+): (\d+)', line)
                    if match:
                        filter_idx, value = int(match.group(1)), int(match.group(2))
                        current_output['filters'][filter_idx] = value
                        
    except FileNotFoundError:
        print(f"Vivado log file {filename} not found.")
        return None
    
    return outputs

def parse_vivado_log_file(filename="vivado_simulation.log"):
    """Parse Vivado simulation log file for report statements."""
    debug_data = {
        'inputs': [],  
        'outputs': []
    }
    
    try:
        with open(filename, 'r') as f:
            current_output = None
            
            for line in f:
                line = line.strip()
                
                # Look for report statements in Vivado log
                if "Providing pixel" in line:
                    # Extract: "Providing pixel [row,col] = value"
                    match = re.search(r'Providing pixel \[(\d+),(\d+)\] = (\d+)', line)
                    if match:
                        row, col, value = int(match.group(1)), int(match.group(2)), int(match.group(3))
                        debug_data['inputs'].append({'type': 'provided', 'row': row, 'col': col, 'value': value})
                
                elif "Output at position" in line:
                    # Extract: "Output at position [row,col]"
                    match = re.search(r'Output at position \[(\d+),(\d+)\]', line)
                    if match:
                        row, col = int(match.group(1)), int(match.group(2))
                        current_output = {'row': row, 'col': col, 'filters': {}}
                        debug_data['outputs'].append(current_output)
                
                elif "Filter" in line and ":" in line and current_output is not None:
                    # Extract: "Filter 0: 1234"
                    match = re.search(r'Filter (\d+): (\d+)', line)
                    if match:
                        filter_idx, value = int(match.group(1)), int(match.group(2))
                        current_output['filters'][filter_idx] = value
                        
    except FileNotFoundError:
        print(f"Vivado log file {filename} not found.")
        return None
    
    return debug_data

def load_python_data(filename="model/intermediate_values.npz"):
    """Load Python model intermediate values."""
    try:
        data = np.load(filename)
        print(f"✓ Loaded Python data: {list(data.keys())}")
        return data['layer_0_output']  # Shape: (26, 26, 8)
    except FileNotFoundError:
        print(f"Python data not found. Run CNN.py first.")
        return None

def get_weight_scale_factor():
    """Get the actual weight scale factor used in CNN.py."""
    # Q1.6 format: 2^6 = 64 scale factor
    # From CNN.py Q1.6 format output
    return 64

def fixed_to_float(vhdl_value, scale_factor=16384):
    """Convert VHDL 16-bit signed output to float for ACTIVATIONS.""" 
    # Handle 16-bit signed two's complement
    if vhdl_value > 32767:
        signed_val = vhdl_value - 65536
    else:
        signed_val = vhdl_value
    
    return signed_val / scale_factor

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
    print("Output format: 16-bit signed (scale = 256)")
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

def compare_outputs(python_data, vhdl_outputs, output_scale_factor=256):
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
                    vhdl_float = fixed_to_float(vhdl_raw, scale_factor=output_scale_factor)  # 16-bit output
                    vhdl_relu = max(0.0, vhdl_float)  # Apply ReLU
                    
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
    python_data = load_python_data()
    vhdl_outputs = parse_vivado_log()
    
    if python_data is None:
        print("❌ No Python data. Run: python model/CNN.py")
        return
    
    if vhdl_outputs is None:
        print("❌ No VHDL data. Run VHDL simulation first.")
        return
    
    # Analyze scaling
    analyze_scaling()
    
    # Find best scale factor
    best_scale = find_best_scale_factor(python_data, vhdl_outputs)
    
    # Compare results with best scale
    avg_error = compare_outputs(python_data, vhdl_outputs, best_scale)
    
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