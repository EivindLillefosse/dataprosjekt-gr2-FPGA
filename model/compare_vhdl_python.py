import re
import numpy as np

# Parse VHDL output file
vhdl_outputs = {}
with open('vivado_project/CNN.sim/sim_1/behav/xsim/modular_intermediate_debug.txt', 'r') as f:
    lines = f.readlines()
    i = 0
    while i < len(lines):
        if lines[i].startswith('MODULAR_OUTPUT:'):
            match = re.search(r'\[(\d+),(\d+)\]', lines[i])
            if match:
                row, col = int(match.group(1)), int(match.group(2))
                filters = []
                for j in range(1, 9):
                    if i+j < len(lines) and lines[i+j].startswith('Filter_'):
                        # Extract decimal value: "Filter_0_hex: 0x39  dec: 57"
                        parts = lines[i+j].split('dec:')
                        if len(parts) >= 2:
                            val = int(parts[1].strip())
                            filters.append(val)
                if len(filters) == 8:
                    vhdl_outputs[(row, col)] = filters
                    i += 9
                    continue
        i += 1

print(f'Parsed {len(vhdl_outputs)} VHDL output positions')

# Load Python reference output
try:
    ref_data = np.load('model/vhdl_conv_reference_output.npz')
    python_output = ref_data['output']
    print(f'Python output shape: {python_output.shape}')
    
    # Compare positions
    match_count = 0
    mismatch_count = 0
    total_compared = 0
    
    for (row, col), vhdl_vals in sorted(vhdl_outputs.items()):
        if row < python_output.shape[0] and col < python_output.shape[1]:
            python_vals = python_output[row, col, :]
            match = all(abs(int(p) - v) <= 1 for p, v in zip(python_vals, vhdl_vals))
            status = 'MATCH' if match else 'MISMATCH'
            if match:
                match_count += 1
            else:
                mismatch_count += 1
            total_compared += 1
            
            # Print first 20 and any mismatches
            if total_compared <= 20 or not match:
                print(f'[{row},{col}] {status}')
                print(f'  VHDL:   {vhdl_vals}')
                print(f'  Python: {[int(p) for p in python_vals]}')
    
    print(f'\n=== Summary ===')
    print(f'Total compared: {total_compared}')
    print(f'Matches: {match_count} ({100*match_count/total_compared:.1f}%)')
    print(f'Mismatches: {mismatch_count} ({100*mismatch_count/total_compared:.1f}%)')
        
except FileNotFoundError:
    print('Python reference output not found. File should be at model/vhdl_conv_reference_output.npz')
