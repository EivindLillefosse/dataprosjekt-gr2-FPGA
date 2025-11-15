"""
Manual FC1 Calculation
======================
Calculate FC1 neuron 54 step-by-step to verify VHDL vs Python discrepancy.

FC1 Layer:
- Input: Pool2 output, flattened to 400 values (5x5x16)
- Weights: 400 inputs × 64 neurons
- Bias: 64 values
- Output: 64 neurons after ReLU

Computation for each neuron n:
  accumulator = sum(input[i] * weight[i][n] for i in range(400)) + bias[n]
  output[n] = max(0, accumulator)  # ReLU
"""

import numpy as np
import re
import tensorflow as tf

def load_pool2_from_debug():
    """Load Pool2 output from VHDL debug file."""
    debug_file = 'vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt'
    
    pool2_values = []
    
    with open(debug_file, 'r') as f:
        lines = f.readlines()
    
    # Find the last LAYER3_POOL2_OUTPUT blocks (one for each of 25 positions)
    # We need to collect all 25 positions in order: [0,0] to [4,4]
    collecting = False
    current_filters = None
    
    for line in lines:
        if line.startswith('LAYER3_POOL2_OUTPUT:'):
            # Start of a new position
            collecting = True
            current_filters = []
        elif collecting and line.strip().startswith('Filter_'):
            # Extract filter value
            parts = line.strip().split(':')
            filter_val = int(parts[1].strip())
            current_filters.append(filter_val)
            
            # After filter 15 (16 filters total), we have complete position
            if len(current_filters) == 16:
                pool2_values.append(current_filters)
                collecting = False
                current_filters = None
    
    # Take last 25 entries (one complete test run)
    pool2_values = pool2_values[-25:]
    
    # Convert to numpy array and reshape to 5x5x16
    pool2_array = np.array(pool2_values, dtype=np.int16).reshape(5, 5, 16)
    
    # Flatten to match FC1 input order (400 values)
    pool2_flat = pool2_array.flatten()
    
    print(f"Loaded Pool2 output: {pool2_array.shape} -> flattened to {pool2_flat.shape}")
    print(f"Pool2 range: [{pool2_flat.min()}, {pool2_flat.max()}]")
    print(f"Pool2 non-zero count: {np.count_nonzero(pool2_flat)}/400")
    
    return pool2_flat, pool2_array

def load_fc1_weights_python(neuron_idx):
    """Load FC1 weights for a specific neuron from Python saved model."""
    print(f"\n=== Loading FC1 weights from Python model ===")
    
    # Load the saved model
    loaded = tf.saved_model.load('model/saved_model')
    
    # Find the Dense layer weights (layer 5 in the model)
    fc1_weights = None
    for var in loaded.trainable_variables:
        if 'dense/kernel' in var.name and 'dense_1' not in var.name:
            fc1_weights = var.numpy()
            break
    
    if fc1_weights is None:
        raise ValueError("Could not find FC1 (dense/kernel) weights in saved model")
    
    print(f"Python FC1 weights shape: {fc1_weights.shape}")  # Should be (400, 64)
    print(f"Python FC1 weights range: [{fc1_weights.min():.6f}, {fc1_weights.max():.6f}]")
    
    # Extract weights for the specified neuron (column in the matrix)
    neuron_weights_float = fc1_weights[:, neuron_idx]
    
    # Quantize to Q1.6 format (same as FPGA export)
    scale = 64
    neuron_weights_q16 = np.round(np.clip(neuron_weights_float, -2.0, 2.0) * scale).astype(np.int8)
    
    print(f"Loaded {len(neuron_weights_q16)} weights for neuron {neuron_idx}")
    print(f"Float range: [{neuron_weights_float.min():.6f}, {neuron_weights_float.max():.6f}]")
    print(f"Q1.6 range: [{neuron_weights_q16.min()}, {neuron_weights_q16.max()}]")
    
    return neuron_weights_q16, neuron_weights_float

def load_fc1_weights_coe(neuron_idx):
    """Load FC1 weights for a specific neuron from COE file."""
    coe_file = 'model/fpga_weights_and_bias/layer_5_dense_weights.coe'
    
    with open(coe_file, 'r') as f:
        content = f.read()
    
    # Extract hex values
    vector_section = content.split('memory_initialization_vector=')[1].split(';')[0]
    hex_values = re.findall(r'[0-9A-Fa-f]{2}', vector_section)
    
    print(f"\nTotal hex bytes in COE: {len(hex_values)}")
    
    # COE layout: 400 addresses (one per input)
    # Each address contains 64 bytes (one per neuron), MSB-first
    # Address format: [neuron_63_weight][neuron_62_weight]...[neuron_0_weight]
    # For neuron N: byte position in each address is (63 - N)
    
    weights = []
    byte_offset = 63 - neuron_idx  # Position within each 64-byte word
    
    for addr in range(400):
        # Each address has 64 bytes (512 bits)
        base_idx = addr * 64
        weight_hex = hex_values[base_idx + byte_offset]
        
        # Convert hex to signed 8-bit integer
        weight_int = int(weight_hex, 16)
        if weight_int > 127:
            weight_int -= 256
        
        weights.append(weight_int)
    
    weights_array = np.array(weights, dtype=np.int8)
    print(f"Loaded {len(weights)} weights for neuron {neuron_idx}")
    print(f"Weight range: [{weights_array.min()}, {weights_array.max()}]")
    
    return weights_array

def load_fc1_bias_python(neuron_idx):
    """Load FC1 bias for a specific neuron from Python saved model."""
    # Load the saved model
    loaded = tf.saved_model.load('model/saved_model')
    
    # Find the Dense layer bias (layer 5 in the model)
    fc1_bias = None
    for var in loaded.trainable_variables:
        if 'dense/bias' in var.name and 'dense_1' not in var.name:
            fc1_bias = var.numpy()
            break
    
    if fc1_bias is None:
        raise ValueError("Could not find FC1 (dense/bias) in saved model")
    
    # Get bias for the specified neuron
    bias_float = fc1_bias[neuron_idx]
    
    # Quantize to Q1.6 format
    scale = 64
    bias_q16 = int(np.round(np.clip(bias_float, -2.0, 2.0) * scale))
    
    print(f"\n=== FC1 Bias for Neuron {neuron_idx} (from Python) ===")
    print(f"Float value: {bias_float:.6f}")
    print(f"Q1.6 value: {bias_q16}")
    
    return bias_q16, bias_float

def load_fc1_bias_coe(neuron_idx):
    """Load FC1 bias for a specific neuron from COE file."""
    coe_file = 'model/fpga_weights_and_bias/layer_5_dense_biases.coe'
    
    with open(coe_file, 'r') as f:
        content = f.read()
    
    # Extract hex values
    vector_section = content.split('memory_initialization_vector=')[1].split(';')[0]
    hex_values = re.findall(r'[0-9A-Fa-f]{2}', vector_section)
    
    # Biases: one byte per neuron (64 total)
    bias_hex = hex_values[neuron_idx]
    bias_int = int(bias_hex, 16)
    if bias_int > 127:
        bias_int -= 256
    
    print(f"\nBias for neuron {neuron_idx}: 0x{bias_hex} = {bias_int} (Q1.6 integer)")
    print(f"Bias as float: {bias_int / 64.0:.6f}")
    
    return bias_int

def compute_neuron_vhdl_style(pool2_flat, weights, bias, neuron_idx):
    """
    Compute neuron output using VHDL-style fixed-point arithmetic.
    
    VHDL Process:
    1. MAC: multiply Q1.6 input × Q1.6 weight = Q2.12 product
    2. Accumulate 400 products
    3. Add bias (scaled to Q2.12 format)
    4. Apply ReLU
    5. Output is 16-bit Q9.6 or similar
    """
    print(f"\n{'='*70}")
    print(f"Computing Neuron {neuron_idx} - VHDL Style (Fixed-Point Q1.6)")
    print(f"{'='*70}")
    
    # VHDL uses 8-bit Q1.6 format: 1 integer bit, 6 fractional bits
    # Scale factor: 64 (2^6)
    Q_SCALE = 64
    
    # Accumulator: sum of products
    # Each product: (8-bit Q1.6) × (8-bit Q1.6) = 16-bit Q2.12
    # But we store as integer, so product range is much larger
    
    accumulator = 0
    
    print(f"\nInput: {len(pool2_flat)} values (Pool2 flattened)")
    print(f"Weights: {len(weights)} values (one per input)")
    print(f"Bias: {bias} (Q1.6 integer)")
    
    # Show first few non-zero computations
    print(f"\nFirst 10 non-zero MAC operations:")
    shown = 0
    for i in range(400):
        input_val = pool2_flat[i]
        weight_val = weights[i]
        
        # VHDL MAC: signed multiplication
        product = input_val * weight_val
        accumulator += product
        
        if input_val != 0 and shown < 10:
            print(f"  [{i:3d}] input={input_val:4d} × weight={weight_val:4d} = {product:8d}  (acc={accumulator:10d})")
            shown += 1
    
    print(f"\nAccumulator after 400 MACs: {accumulator}")
    
    # Add bias (bias is in Q1.6 format, need to scale to match accumulator)
    # If accumulator is sum of (Q1.6 × Q1.6), then it's effectively Q2.12 scale
    # But bias is Q1.6, so we multiply by Q_SCALE to match
    bias_scaled = bias * Q_SCALE
    accumulator_with_bias = accumulator + bias_scaled
    
    print(f"Bias (Q1.6): {bias}")
    print(f"Bias scaled (×{Q_SCALE}): {bias_scaled}")
    print(f"Accumulator + bias: {accumulator_with_bias}")
    
    # ReLU: max(0, value)
    output_relu = max(0, accumulator_with_bias)
    print(f"After ReLU: {output_relu}")
    
    # Convert to float for comparison
    # If accumulator represents Q2.12 format (scale = 4096)
    output_float_q212 = output_relu / 4096.0
    # If accumulator represents Q9.6 format (scale = 64)
    output_float_q96 = output_relu / 64.0
    
    print(f"\nAs float (Q2.12, scale=4096): {output_float_q212:.6f}")
    print(f"As float (Q9.6, scale=64): {output_float_q96:.6f}")
    
    return {
        'accumulator': accumulator,
        'accumulator_with_bias': accumulator_with_bias,
        'output_relu': output_relu,
        'output_float_q212': output_float_q212,
        'output_float_q96': output_float_q96
    }

def compute_neuron_python_style(pool2_python, neuron_idx):
    """
    Compute neuron output using Python's floating-point values.
    """
    print(f"\n{'='*70}")
    print(f"Computing Neuron {neuron_idx} - Python Style (Floating-Point)")
    print(f"{'='*70}")
    
    # Load Python intermediate values
    data = np.load('model/intermediate_values.npz')
    
    # Pool2 output (before flatten)
    pool2_output = data['layer_3_output']  # Shape: (5, 5, 16)
    print(f"Pool2 shape: {pool2_output.shape}")
    print(f"Pool2 range: [{pool2_output.min():.6f}, {pool2_output.max():.6f}]")
    
    # Flatten
    pool2_flat = pool2_output.flatten()  # 400 values
    print(f"Flattened: {pool2_flat.shape}")
    
    # FC1 output
    fc1_output = data['layer_5_output']  # Shape: (64,)
    neuron_output = fc1_output[neuron_idx]
    
    print(f"\nFC1 neuron {neuron_idx} output: {neuron_output:.6f}")
    
    return {
        'pool2_flat': pool2_flat,
        'fc1_output': neuron_output
    }

def main():
    print("Manual FC1 Calculation - Neuron 54")
    print("="*70)
    
    neuron_idx = 54
    
    # Load VHDL Pool2 output
    print("\n" + "="*70)
    print("STEP 1: Load Pool2 Output from VHDL Debug File")
    print("="*70)
    pool2_vhdl_flat, pool2_vhdl_array = load_pool2_from_debug()
    
    # Load weights from PYTHON model
    print("\n" + "="*70)
    print("STEP 2: Load Weights from PYTHON Model")
    print("="*70)
    weights_q16, weights_float = load_fc1_weights_python(neuron_idx)
    
    # Also load from COE for comparison
    print("\n" + "="*70)
    print("STEP 2b: Load Weights from COE File (for comparison)")
    print("="*70)
    weights_coe = load_fc1_weights_coe(neuron_idx)
    
    # Compare weights
    print("\n" + "="*70)
    print("WEIGHT COMPARISON: Python vs COE")
    print("="*70)
    weight_diff = weights_q16 - weights_coe
    print(f"Differences: {np.count_nonzero(weight_diff)} out of {len(weight_diff)}")
    if np.count_nonzero(weight_diff) > 0:
        print(f"Max difference: {np.max(np.abs(weight_diff))}")
        print(f"Indices with differences: {np.where(weight_diff != 0)[0][:20].tolist()}...")
        print(f"Example differences (first 10):")
        diff_idx = np.where(weight_diff != 0)[0][:10]
        for idx in diff_idx:
            print(f"  Input {idx}: Python={weights_q16[idx]}, COE={weights_coe[idx]}, diff={weight_diff[idx]}")
    else:
        print("✅ All weights match perfectly!")
    
    # Load bias from PYTHON model
    print("\n" + "="*70)
    print("STEP 3: Load Bias from PYTHON Model")
    print("="*70)
    bias_q16, bias_float = load_fc1_bias_python(neuron_idx)
    
    # Also load from COE for comparison
    print("\n" + "="*70)
    print("STEP 3b: Load Bias from COE File (for comparison)")
    print("="*70)
    bias_coe = load_fc1_bias_coe(neuron_idx)
    
    print(f"\nBias comparison: Python={bias_q16}, COE={bias_coe}, match={bias_q16 == bias_coe}")
    
    # Compute VHDL-style with PYTHON weights
    print("\n" + "="*70)
    print("STEP 4: Compute Neuron Output (VHDL Fixed-Point, PYTHON Weights)")
    print("="*70)
    vhdl_result_python = compute_neuron_vhdl_style(pool2_vhdl_flat, weights_q16, bias_q16, neuron_idx)
    
    # Compute VHDL-style with COE weights
    print("\n" + "="*70)
    print("STEP 4b: Compute Neuron Output (VHDL Fixed-Point, COE Weights)")
    print("="*70)
    vhdl_result_coe = compute_neuron_vhdl_style(pool2_vhdl_flat, weights_coe, bias_coe, neuron_idx)
    
    # Get Python result
    print("\n" + "="*70)
    print("STEP 5: Compare with Python Floating-Point")
    print("="*70)
    python_result = compute_neuron_python_style(pool2_vhdl_flat, neuron_idx)
    
    # Load actual VHDL debug output
    print("\n" + "="*70)
    print("STEP 6: Compare with Actual VHDL Output")
    print("="*70)
    
    debug_file = 'vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt'
    with open(debug_file, 'r') as f:
        content = f.read()
    
    # Find last FC1_OUTPUT block
    fc1_blocks = content.split('FC1_OUTPUT:')
    if len(fc1_blocks) > 1:
        last_block = fc1_blocks[-1]
        lines = last_block.split('\n')
        for line in lines:
            if f'Neuron_{neuron_idx}:' in line:
                vhdl_actual = int(line.split(':')[1].strip())
                print(f"VHDL actual output for neuron {neuron_idx}: {vhdl_actual}")
                break
    
    # Summary comparison
    print("\n" + "="*70)
    print("SUMMARY")
    print("="*70)
    print(f"Neuron {neuron_idx} Results:")
    print(f"  Manual calc with PYTHON weights: {vhdl_result_python['output_relu']}")
    print(f"  Manual calc with COE weights:    {vhdl_result_coe['output_relu']}")
    print(f"  Actual VHDL output:               {vhdl_actual}")
    print()
    print(f"  Match with PYTHON weights: {vhdl_result_python['output_relu'] == vhdl_actual}")
    print(f"  Match with COE weights:    {vhdl_result_coe['output_relu'] == vhdl_actual}")
    print()
    print(f"  Python weights as float (Q2.12): {vhdl_result_python['output_float_q212']:.6f}")
    print(f"  COE weights as float (Q2.12):    {vhdl_result_coe['output_float_q212']:.6f}")
    print(f"  Python FC1 output (expected):    {python_result['fc1_output']:.6f}")

if __name__ == '__main__':
    main()
