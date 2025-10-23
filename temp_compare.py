import re
import numpy as np

# Load Python reference
ref_data = np.load('model/vhdl_conv_reference_output.npz')
python_output = ref_data['output']

# Parse just first few VHDL positions
with open('vivado_project/CNN.sim/sim_1/behav/xsim/modular_intermediate_debug.txt', 'r') as f:
    lines = f.readlines()
    
positions_found = 0
i = 0
while i < len(lines) and positions_found < 10:
    if lines[i].startswith('MODULAR_OUTPUT:'):
        match = re.search(r'\[(\d+),(\d+)\]', lines[i])
        if match:
            row, col = int(match.group(1)), int(match.group(2))
            filters = []
            for j in range(1, 9):
                if i+j < len(lines) and lines[i+j].startswith('Filter_'):
                    val = int(lines[i+j].split(': ')[1].strip())
                    filters.append(val)
            if len(filters) == 8 and row < python_output.shape[0] and col < python_output.shape[1]:
                python_vals = list(python_output[row, col, :].astype(int))
                match = all(abs(p - v) <= 1 for p, v in zip(python_vals, filters))
                print(f'[{row},{col}] {"MATCH" if match else "MISMATCH"}')
                print(f'  VHDL:   {filters}')
                print(f'  Python: {python_vals}')
                print()
                positions_found += 1
            i += 9
            continue
    i += 1
