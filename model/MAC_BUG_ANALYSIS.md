# MAC Unit Q-Format Bug Analysis

## Problem Summary
VHDL convolution layer outputs are approximately **64x smaller** than expected.
- **Python reference output at [0,1], Filter 1**: 73 (Q1.6 format)
- **VHDL output at [0,1], Filter 1**: 1 (Q1.6 format)

## Root Cause
The MAC unit accumulates Q1.6 products directly **without shifting to Q2.12 format**.

### Expected Behavior (Python Reference)
`python
# For each multiplication:
product_q1_6 = weight * pixel      # Q1.6 * uint8 = Q1.6
product_q2_12 = product_q1_6 << 6  # Shift to Q2.12 for accumulation
acc_q2_12 += product_q2_12         # Accumulate in Q2.12

# After all products:
bias_q2_12 = bias << 6              # Convert bias to Q2.12
acc_q2_12 += bias_q2_12             # Add bias
scaled_q1_6 = acc_q2_12 >> 6        # Scale back to Q1.6
`

### Actual Behavior (VHDL MAC)
`hdl
-- The MACC_MACRO simply does: result = A * B + result
-- No shift to Q2.12!
acc_q1_6 += weight * pixel  -- Accumulates in Q1.6 directly
`

## Example Calculation (Position [0,1], Filter 1)

### Input Region
`
[2, 3, 4]
[3, 4, 5]
[4, 5, 6]
`

### Filter 1 Weights (Q1.6)
`
[ 3, 14, -8]
[ 7, 10, -15]
[-4,  1,  14]
`

### Products
| Pixel | Weight | Q1.6 Product | Q2.12 Product (shifted) |
|-------|--------|--------------|-------------------------|
| 2     | 3      | 6            | 384                     |
| 3     | 14     | 42           | 2688                    |
| 4     | -8     | -32          | -2048                   |
| 3     | 7      | 21           | 1344                    |
| 4     | 10     | 40           | 2560                    |
| 5     | -15    | -75          | -4800                   |
| 4     | -4     | -16          | -1024                   |
| 5     | 1      | 5            | 320                     |
| 6     | 14     | 84           | 5376                    |

### Accumulation
- **VHDL (Q1.6)**: 6+42-32+21+40-75-16+5+84 = **75**
- **Python (Q2.12)**: 384+2688-2048+1344+2560-4800-1024+320+5376 = **4800**

### After Bias (-2 in Q1.6 = -128 in Q2.12)
- **VHDL**: 75 (no conversion) → after fake-bias processing → **~1**
- **Python**: 4800 - 128 = 4672 (Q2.12)

### After Scaling (>>6)
- **VHDL**: ~1 (already in wrong format)
- **Python**: 4672 >> 6 = **73** ✓

### After ReLU
- **VHDL**: 1
- **Python**: 73

## Fix Required

The MAC unit needs to be modified to shift each product left by 6 bits before accumulation:

### Option 1: Modify MAC Unit
Add a shifter between the multiplier output and the accumulator.

### Option 2: Post-Shift in Convolution Engine
Shift the MAC result left by 6 after each product before passing to accumulator.

### Option 3: Use Wider Accumulator
Configure the MACC_MACRO to output in Q2.12 format by adjusting the fixed-point position.

## Impact
- **All convolution layer outputs are incorrect by a factor of ~64**
- Explains the massive mismatch between VHDL and Python outputs
- Critical bug that prevents correct CNN operation

## Verification Plan
1. Create MAC testbench (MAC_tb.vhd) - ✓ Created
2. Run testbench to confirm Q1.6 vs Q2.12 behavior
3. Implement fix in MAC or convolution engine
4. Re-run conv_layer_modular_tb to verify correct outputs
5. Compare with Python reference - should match within ±1 LSB

