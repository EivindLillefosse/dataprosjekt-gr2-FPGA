#!/usr/bin/env python3
"""
Debug Comparison Tool for CNN FPGA Implementation
Compares intermediate values between Python model and VHDL simulation
"""

import numpy as np
import re
import matplotlib.pyplot as plt
import os
import csv

def parse_vhdl_debug_file(filename="intermediate_debug.txt"):
    """Parse VHDL debug output file."""
    debug_data = {
        'inputs': [],
        'outputs': []
    }
    
    try:
        with open(filename, 'r') as f:
            for line in f:
                line = line.strip()
                
                # Parse input requests
                if line.startswith("INPUT_REQUEST:"):
                    match = re.search(r'\[(\d+),(\d+)\]', line)
                    if match:
                        row, col = int(match.group(1)), int(match.group(2))
                        debug_data['inputs'].append({'type': 'request', 'row': row, 'col': col})
                
                # Parse input provisions
                elif line.startswith("INPUT_PROVIDED:"):
                    match = re.search(r'\[(\d+),(\d+)\] = (\d+)', line)
                    if match:
                        row, col, value = int(match.group(1)), int(match.group(2)), int(match.group(3))
                        debug_data['inputs'].append({'type': 'provided', 'row': row, 'col': col, 'value': value})
                
                # Parse outputs
                elif line.startswith("OUTPUT:"):
                    match = re.search(r'\[(\d+),(\d+)\]', line)
                    if match:
                        row, col = int(match.group(1)), int(match.group(2))
                        debug_data['outputs'].append({'row': row, 'col': col, 'filters': {}})
                
                # Parse filter outputs
                elif "Filter_" in line:
                    match = re.search(r'Filter_(\d+): (\d+)', line)
                    if match and debug_data['outputs']:
                        filter_idx, value = int(match.group(1)), int(match.group(2))
                        debug_data['outputs'][-1]['filters'][filter_idx] = value
                        
    except FileNotFoundError:
        print(f"Debug file {filename} not found. Run VHDL simulation first.")
        return None
    
    return debug_data

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

def parse_csv_export(filename="simulation_data.csv"):
    """Parse CSV data exported from Vivado."""
    debug_data = {
        'inputs': [],
        'outputs': [],
        'signals': {}
    }
    
    try:
        with open(filename, 'r') as f:
            reader = csv.DictReader(f)
            
            for row in reader:
                # Assuming CSV has columns: time, signal_name, value
                time = row.get('time', '0')
                signal = row.get('signal_name', '')
                value = row.get('value', '0')
                
                # Parse specific signals
                if 'input_pixel' in signal and 'input_valid' in row and row['input_valid'] == '1':
                    # Extract position from other columns if available
                    r = int(row.get('input_row', 0))
                    c = int(row.get('input_col', 0))
                    v = int(value, 16) if value.startswith('x') else int(value)
                    debug_data['inputs'].append({'type': 'provided', 'row': r, 'col': c, 'value': v})
                
                elif 'output_pixel' in signal and 'output_valid' in row and row['output_valid'] == '1':
                    r = int(row.get('output_row', 0))
                    c = int(row.get('output_col', 0))
                    # Handle array signals
                    if signal not in debug_data['signals']:
                        debug_data['signals'][signal] = []
                    debug_data['signals'][signal].append({'time': time, 'row': r, 'col': c, 'value': value})
                        
    except FileNotFoundError:
        print(f"CSV file {filename} not found.")
        return None
    except Exception as e:
        print(f"Error parsing CSV: {e}")
        return None
    
    return debug_data

def load_python_intermediate_values(filename="model/intermediate_values.npz"):
    """Load Python model intermediate values."""
    try:
        data = np.load(filename)
        return {key: data[key] for key in data.keys()}
    except FileNotFoundError:
        print(f"Python intermediate values file {filename} not found.")
        print("Run CNN.py with TEST_ENABLED=True first.")
        return None

def compare_convolution_step(python_data, vhdl_data, position):
    """Compare a single convolution step between Python and VHDL."""
    print(f"\n=== Comparing Convolution at Position {position} ===")
    
    # Find corresponding VHDL output
    vhdl_output = None
    for output in vhdl_data['outputs']:
        if (output['row'], output['col']) == position:
            vhdl_output = output
            break
    
    if vhdl_output is None:
        print(f"No VHDL output found for position {position}")
        return
    
    # Get Python conv layer output at this position
    conv_output_key = None
    for key in python_data.keys():
        if 'layer_0_' in key and 'filter_' in key:  # First conv layer
            conv_output_key = key
            break
    
    if conv_output_key is None:
        print("No Python conv layer output found")
        return
    
    # Compare filter by filter
    python_conv = python_data[conv_output_key]
    row, col = position
    
    print("Filter Comparison:")
    print("Filter | Python    | VHDL      | VHDL(16bit) | Difference")
    print("-------|-----------|-----------|-------------|----------")
    
    for filter_idx in range(min(8, len(vhdl_output['filters']))):
        if row < python_conv.shape[0] and col < python_conv.shape[1]:
            python_val = python_conv[row, col] if len(python_conv.shape) == 2 else python_conv[row, col]
            vhdl_val_raw = vhdl_output['filters'].get(filter_idx, 0)
            
            # Convert VHDL 16-bit unsigned to signed for comparison
            if vhdl_val_raw > 32767:
                vhdl_val_signed = vhdl_val_raw - 65536
            else:
                vhdl_val_signed = vhdl_val_raw
            
            diff = abs(python_val - vhdl_val_signed)
            
            print(f"{filter_idx:6d} | {python_val:9.3f} | {vhdl_val_raw:9d} | {vhdl_val_signed:9d} | {diff:9.3f}")
    
    # Check if Python data might be from different test
    if python_val == 0.0:
        print("\n⚠️  Python model shows 0.0 - may be using different test data")
        print("   Consider running CNN.py with the same 28x28 test pattern as VHDL")

def generate_test_vectors():
    """Generate test vectors for VHDL simulation."""
    print("\n=== Generating Test Vectors ===")
    
    # Create a simple 3x3 test pattern for easier debugging
    test_pattern = np.array([
        [1, 2, 3],
        [4, 5, 6], 
        [7, 8, 9]
    ])
    
    # Generate VHDL constant declaration
    with open('model/test_vectors.vhd', 'w') as f:
        f.write("-- Test vectors for convolution debugging\n")
        f.write("-- Simple 3x3 pattern for verification\n\n")
        
        f.write("constant test_pattern : test_image_type := (\n")
        for i in range(3):
            f.write("    (")
            for j in range(3):
                if j < 2:
                    f.write(f"{test_pattern[i,j]}, ")
                else:
                    f.write(f"{test_pattern[i,j]}")
            if i < 2:
                f.write("),\n")
            else:
                f.write(")\n")
        f.write(");\n")
    
    print("✓ Test vectors saved to model/test_vectors.vhd")
    return test_pattern

def manual_convolution_check(image, kernel, position):
    """Manually compute convolution for verification."""
    row, col = position
    result = 0
    
    print(f"\nManual convolution check at position ({row}, {col}):")
    print("Image region | Kernel | Product")
    print("-------------|--------|--------")
    
    for i in range(3):
        for j in range(3):
            img_row, img_col = row + i - 1, col + j - 1  # Center kernel at position
            
            # Handle padding
            if img_row < 0 or img_row >= image.shape[0] or img_col < 0 or img_col >= image.shape[1]:
                img_val = 0
            else:
                img_val = image[img_row, img_col]
            
            kernel_val = kernel[i, j]
            product = img_val * kernel_val
            result += product
            
            print(f"{img_val:11d} | {kernel_val:6d} | {product:7d}")
    
    print(f"Total result: {result}")
    return result

def analyze_timing_sequence(vhdl_data):
    """Analyze the timing sequence of VHDL operations."""
    print("\n=== Timing Analysis ===")
    
    inputs = [inp for inp in vhdl_data['inputs'] if inp['type'] == 'provided']
    outputs = vhdl_data['outputs']
    
    print(f"Total input sequences: {len(inputs)}")
    print(f"Total output sequences: {len(outputs)}")
    
    if len(inputs) > 0:
        print("\nFirst 10 input sequences:")
        for i, inp in enumerate(inputs[:10]):
            print(f"  {i+1:2d}: [{inp['row']:2d},{inp['col']:2d}] = {inp['value']:3d}")
    
    if len(outputs) > 0:
        print(f"\nFirst 5 output sequences:")
        for i, out in enumerate(outputs[:5]):
            filter_count = len(out['filters'])
            print(f"  {i+1:2d}: [{out['row']:2d},{out['col']:2d}] -> {filter_count} filters")

def analyze_vhdl_output_patterns(vhdl_data):
    """Analyze VHDL output patterns for common issues."""
    print("\n=== VHDL Output Analysis ===")
    
    if not vhdl_data or not vhdl_data['outputs']:
        print("No VHDL outputs to analyze")
        return
    
    # Collect all filter values
    all_values = []
    for output in vhdl_data['outputs']:
        for filter_idx, value in output['filters'].items():
            all_values.append(value)
    
    if not all_values:
        print("No filter values found")
        return
    
    # Analyze value ranges
    min_val = min(all_values)
    max_val = max(all_values)
    
    print(f"Value range: {min_val} to {max_val}")
    
    # Check for 16-bit overflow patterns
    large_values = [v for v in all_values if v > 32767]
    if large_values:
        print(f"⚠️  Found {len(large_values)} values > 32767 (potential 16-bit overflow)")
        print(f"   Examples: {large_values[:5]}")
        
        # Convert to signed interpretation
        signed_examples = [v - 65536 if v > 32767 else v for v in large_values[:5]]
        print(f"   As signed 16-bit: {signed_examples}")
    
    # Look for patterns in first few outputs
    print(f"\nFirst 3 outputs analysis:")
    for i, output in enumerate(vhdl_data['outputs'][:3]):
        print(f"  Position [{output['row']},{output['col']}]:")
        for filter_idx in sorted(output['filters'].keys()):
            raw_val = output['filters'][filter_idx]
            signed_val = raw_val - 65536 if raw_val > 32767 else raw_val
            print(f"    Filter {filter_idx}: {raw_val} -> {signed_val}")

def generate_detailed_report(python_data, vhdl_data):
    """Generate a detailed comparison report."""
    print("\n=== Detailed Analysis Report ===")
    
    # Check data availability
    if python_data is None and vhdl_data is None:
        print("❌ No data available for comparison")
        return
    elif python_data is None:
        print("⚠️  Python data missing - only VHDL analysis available")
        analyze_timing_sequence(vhdl_data)
        analyze_vhdl_output_patterns(vhdl_data)
        return
    elif vhdl_data is None:
        print("⚠️  VHDL data missing - only Python analysis available")
        print(f"Python layers: {list(python_data.keys())}")
        return
    
    # Full comparison available
    print("✓ Both Python and VHDL data available")
    
    # Analyze input coverage
    vhdl_inputs = [(inp['row'], inp['col']) for inp in vhdl_data['inputs'] if inp['type'] == 'provided']
    unique_positions = set(vhdl_inputs)
    print(f"VHDL processed {len(vhdl_inputs)} inputs at {len(unique_positions)} unique positions")
    
    # Analyze output coverage
    vhdl_outputs = [(out['row'], out['col']) for out in vhdl_data['outputs']]
    print(f"VHDL generated {len(vhdl_outputs)} outputs")
    
    # Check for missing filters in outputs
    if len(vhdl_data['outputs']) > 0:
        filter_counts = [len(out['filters']) for out in vhdl_data['outputs']]
        print(f"Filters per output: min={min(filter_counts)}, max={max(filter_counts)}, avg={np.mean(filter_counts):.1f}")
        
        # Look for incomplete outputs
        incomplete = [i for i, count in enumerate(filter_counts) if count < 8]  # Assuming 8 filters
        if incomplete:
            print(f"⚠️  {len(incomplete)} outputs have incomplete filter data")
    
    # Analyze VHDL patterns
    analyze_vhdl_output_patterns(vhdl_data)

def auto_detect_vivado_data():
    """Automatically detect available Vivado data files."""
    data_sources = []
    
    # Check for different file types
    if os.path.exists("intermediate_debug.txt"):
        data_sources.append(("VHDL Debug File", "intermediate_debug.txt", parse_vhdl_debug_file))
    
    if os.path.exists("vivado.log"):
        data_sources.append(("Vivado Log", "vivado.log", parse_vivado_log_file))
    
    if os.path.exists("simulation_data.csv"):
        data_sources.append(("CSV Export", "simulation_data.csv", parse_csv_export))
    
    # Look for log files in vivado_project directory
    vivado_log_path = "vivado_project/CNN.sim/sim_1/behav/xsim/elaborate.log"
    if os.path.exists(vivado_log_path):
        data_sources.append(("Vivado Sim Log", vivado_log_path, parse_vivado_log_file))
    
    return data_sources

def main():
    """Main comparison function."""
    print("CNN FPGA Debug Comparison Tool")
    print("=" * 40)
    
    # Load Python data
    python_data = load_python_intermediate_values()
    
    # Auto-detect VHDL/Vivado data sources
    data_sources = auto_detect_vivado_data()
    
    if not data_sources:
        print("❌ No Vivado data files found!")
        print("\nExpected files:")
        print("  - intermediate_debug.txt (from VHDL testbench)")
        print("  - vivado.log (from Vivado simulation)")
        print("  - simulation_data.csv (exported from Vivado)")
        vhdl_data = None
    else:
        print(f"✓ Found {len(data_sources)} potential data sources:")
        for i, (name, path, _) in enumerate(data_sources):
            print(f"  {i+1}. {name}: {path}")
        
        # Try to load from the first source
        name, path, parser = data_sources[0]
        print(f"\nUsing: {name}")
        vhdl_data = parser(path)
    
    # Generate detailed report regardless of data availability
    generate_detailed_report(python_data, vhdl_data)
    
    # Only proceed with comparison if both datasets are available
    if python_data is not None and vhdl_data is not None:
        # Generate test vectors for easier debugging
        test_pattern = generate_test_vectors()
        
        # Example kernel for manual verification
        example_kernel = np.array([
            [1, 0, -1],
            [2, 0, -2], 
            [1, 0, -1]
        ])
        
        # Compare first few positions
        positions_to_check = [(0, 0), (0, 1), (1, 0), (1, 1)]
        
        for pos in positions_to_check:
            if len(vhdl_data['outputs']) > 0:
                compare_convolution_step(python_data, vhdl_data, pos)
                
                # Manual verification
                manual_result = manual_convolution_check(test_pattern, example_kernel, pos)
    else:
        print("\n⚠️  Skipping detailed comparison - missing data files")
        print("\nTo generate missing files:")
        if python_data is None:
            print("  - Run: python model/CNN.py (with TEST_ENABLED=True)")
        if vhdl_data is None:
            print("  - Run VHDL simulation to generate intermediate_debug.txt")
    
    print("\n=== Debugging Recommendations ===")
    if vhdl_data and vhdl_data['outputs']:
        # Check if we have overflow patterns
        all_values = []
        for output in vhdl_data['outputs']:
            for filter_idx, value in output['filters'].items():
                all_values.append(value)
        
        if all_values and max(all_values) > 32767:
            print("🔧 VHDL Issue: 16-bit overflow detected")
            print("   - Check MAC accumulator width")
            print("   - Verify weight quantization scaling")
            print("   - Consider adding saturation logic")
        
        if python_data:
            # Check if Python values are all zero
            python_vals = []
            for key in python_data.keys():
                if 'layer_0_' in key and 'filter_' in key:
                    data = python_data[key]
                    python_vals.extend(data.flatten())
            
            if python_vals and max(abs(v) for v in python_vals) < 0.001:
                print("🔧 Python Issue: All values near zero")
                print("   - Run CNN.py with TEST_ENABLED=True")
                print("   - Ensure same test pattern as VHDL")
                print("   - Check if ReLU is zeroing out negative values")
    
    print("\n=== Usage Tips ===")
    print("1. Start with small test patterns (3x3 or 4x4 images)")
    print("2. Verify input/output handshaking timing first")
    print("3. Check filter-by-filter for systematic errors")
    print("4. Use manual_convolution_check() for step-by-step verification")
    print("5. Pay attention to 16-bit signed/unsigned interpretation")
    print("6. Ensure Python and VHDL use identical test data")

if __name__ == "__main__":
    main()