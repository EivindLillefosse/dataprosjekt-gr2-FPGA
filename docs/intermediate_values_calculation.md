# How Intermediate Values Are Calculated in the CNN

This document explains step-by-step how the intermediate values are calculated in the CNN model, what weights are used, and how they're organized.

## Overview

The CNN processes a 28×28 input image through multiple layers:
1. **Layer 0**: Conv2D (3×3 kernel, 8 filters) → 26×26×8
2. **Layer 1**: MaxPooling2D (2×2) → 13×13×8
3. **Layer 2**: Conv2D (3×3 kernel, 16 filters) → 11×11×16
4. **Layer 3**: MaxPooling2D (2×2) → 5×5×16
5. **Layer 4**: Flatten → 400 values
6. **Layer 5**: Dense (64 units) → 64 values
7. **Layer 6**: Dense (10 units) → 10 values (output classes)

## Test Input Pattern

The test input used in both Python and VHDL is a 28×28 pattern where:
```
pixel[i,j] = (i + j + 1) mod 256
```

Example (first 5×5 region):
```
 1  2  3  4  5
 2  3  4  5  6
 3  4  5  6  7
 4  5  6  7  8
 5  6  7  8  9
```

## Layer 0: Convolution (3×3, 8 filters)

### Weights and Biases

**Weights shape**: (3, 3, 1, 8) = 72 total weights
- 3×3 kernel size
- 1 input channel
- 8 output filters

**Storage format** (COE file):
- Quantized to Q1.6 format (signed 8-bit integers)
- Packed by kernel position: all 8 filter weights at each (row, col, channel) are stored consecutively
- Dequantize by dividing by 64 (2^6 fractional bits)

**Example - First filter weights** (after dequantization):
```
Filter 0 (3×3×1):
 -0.140625  -0.093750   0.140625
  0.203125  -0.156250  -0.031250
 -0.156250   0.093750   0.156250
```

**Biases**: 8 values (one per filter)
```
[-0.015625, -0.015625, -0.03125, -0.015625, -0.03125, -0.03125, -0.015625, -0.03125]
```

### Calculation Process

For each output position (h, w) and filter f:

1. **Slide 3×3 kernel** over input starting at position (h, w)
2. **Element-wise multiply** each input pixel by corresponding weight
3. **Sum all products** (9 multiplications for 3×3×1)
4. **Add bias** for this filter
5. **Apply ReLU activation**: output = max(0, sum)

### Example Calculation: Output at (0,0) for Filter 0

**Input region** (3×3 starting at position 0,0):
```
1  2  3
2  3  4
3  4  5
```

**Step-by-step multiplication**:
```
kernel[0,0]: input[0,0]=1.00 × weight=-0.1406 = -0.1406 (sum: -0.1406)
kernel[0,1]: input[0,1]=2.00 × weight=-0.0938 = -0.1875 (sum: -0.3281)
kernel[0,2]: input[0,2]=3.00 × weight= 0.1406 =  0.4219 (sum:  0.0938)
kernel[1,0]: input[1,0]=2.00 × weight= 0.2031 =  0.4062 (sum:  0.5000)
kernel[1,1]: input[1,1]=3.00 × weight=-0.1562 = -0.4688 (sum:  0.0312)
kernel[1,2]: input[1,2]=4.00 × weight=-0.0312 = -0.1250 (sum: -0.0938)
kernel[2,0]: input[2,0]=3.00 × weight=-0.1562 = -0.4688 (sum: -0.5625)
kernel[2,1]: input[2,1]=4.00 × weight= 0.0938 =  0.3750 (sum: -0.1875)
kernel[2,2]: input[2,2]=5.00 × weight= 0.1562 =  0.7812 (sum:  0.5938)
```

**Add bias**:
```
0.5938 + (-0.0156) = 0.5781
```

**Apply ReLU**:
```
max(0, 0.5781) = 0.5781
```

**Final output**: `output[0,0,0] = 0.5781`

### Sliding Window Pattern

The convolution slides across the entire 28×28 input:
- Start: (0,0) to (2,2)
- Next: (0,1) to (2,3)
- Continue sliding right and down
- Output size: (28-3+1) × (28-3+1) = 26×26

For each of the 8 filters, this produces a 26×26 feature map, resulting in a total output of 26×26×8.

## Layer 1: MaxPooling (2×2)

### Process

1. **Divide** the 26×26 input into 13×13 non-overlapping 2×2 windows
2. For each window and channel, **take the maximum value**
3. **Preserve all channels** independently

### Example

**Input region** for first filter, first pooling window (top-left 2×2):
```
0.5781  0.5938
0.5938  0.6094
```

**Max value**: `0.6094`

**Output**: `pool1[0,0,0] = 0.6094`

Output size: 13×13×8 (one max value per 2×2 window, for each of 8 channels)

## Layer 2: Convolution (3×3, 16 filters)

### Weights and Biases

**Weights shape**: (3, 3, 8, 16) = 1,152 total weights
- 3×3 kernel size
- 8 input channels (from Layer 1 output)
- 16 output filters

**Weight statistics** (after dequantization):
- Range: [-0.203125, 0.234375]
- Mean: -0.006727

**Biases**: 16 values (one per filter)
```
[-0.046875, -0.03125, 0.046875, 0.0, 0.03125, -0.015625, 0.0, -0.015625,
 -0.03125, -0.015625, 0.0, 0.0, -0.03125, -0.015625, -0.015625, -0.015625]
```

### Calculation Process

For each output position (h, w) and filter f:

1. **Slide 3×3 kernel** over **all 8 input channels**
2. **Element-wise multiply** each input pixel by corresponding weight
3. **Sum all products** (72 multiplications: 3×3×8)
4. **Add bias** for this filter
5. **Apply ReLU activation**: output = max(0, sum)

### Multi-channel Convolution

Unlike Layer 0 which had only 1 input channel, Layer 2 processes 8 channels:

```
For each kernel position (kh, kw):
    For each input channel c (0 to 7):
        sum += input[h+kh, w+kw, c] × weight[kh, kw, c, filter_idx]
```

This means each output value is the result of 72 multiply-add operations (3×3 spatial × 8 channels).

## Layer 3: MaxPooling (2×2)

Same as Layer 1, but operates on 11×11×16 input to produce 5×5×16 output.

## Quantization: Q1.6 Format

All weights and biases are stored in Q1.6 fixed-point format:

### Format Details
- **Total bits**: 8 (signed int8)
- **Sign bit**: 1 bit
- **Integer bits**: 1 bit
- **Fractional bits**: 6 bits
- **Scale factor**: 2^6 = 64
- **Range**: -2.0 to +1.984375
- **Step size**: 1/64 = 0.015625

### Conversion

**Floating point → Q1.6**:
```python
# Clamp to valid range
clamped = np.clip(value, -2.0, 1.984375)
# Scale and round
quantized_int8 = round(clamped * 64)
```

**Q1.6 → Floating point**:
```python
dequantized = int8_value / 64.0
```

### Example
```
Floating point: 0.203125
Quantized:      13 (as int8)
Dequantized:    13 / 64 = 0.203125 ✓
```

## Memory Organization in COE Files

### Conv2D Weights (Packed Format)

Weights are packed to optimize BRAM access:

**Layer 0** (8 filters):
- Each BRAM address contains all 8 filter weights for one (kernel_row, kernel_col, channel) position
- Address 0: weights for all 8 filters at kernel position (0,0,0)
- Address 1: weights for all 8 filters at kernel position (0,1,0)
- etc.
- Total addresses: 3×3×1 = 9

**Memory width**: 8 filters × 8 bits/filter = 64 bits per address

**Layer 2** (16 filters):
- Each BRAM address contains all 16 filter weights for one (kernel_row, kernel_col, channel) position
- Total addresses: 3×3×8 = 72
- Memory width: 16 filters × 8 bits/filter = 128 bits per address

### Biases (Unpacked Format)

Biases are stored as individual 8-bit values:
- Address 0: bias for filter 0
- Address 1: bias for filter 1
- etc.

## VHDL Implementation Notes

The VHDL implementation must match these calculations:

1. **MAC (Multiply-Accumulate)**: Performs `accumulator += input × weight`
2. **Precision**: Use sufficient bits to avoid overflow (typically 16-bit for accumulator)
3. **ReLU**: Simple comparison `output = max(0, accumulator + bias)`
4. **Memory unpacking**: Extract individual filter weights from packed BRAM words

### Address Calculation for Weights

```vhdl
-- For Conv2D layer
address = ((kernel_row * K) + kernel_col) * C + channel
-- where K = kernel size (3), C = number of input channels
```

### Weight Unpacking (MSB-first)

For N filters, weights are packed MSB-first:
```vhdl
weight_data(0) <= weight_dout(W*N-1 downto W*N-W)    -- Filter 0 (MSB)
weight_data(1) <= weight_dout(W*N-W-1 downto W*N-2*W) -- Filter 1
...
weight_data(N-1) <= weight_dout(W-1 downto 0)        -- Filter N-1 (LSB)
```

## Running the Analysis Scripts

Two Python scripts are provided for detailed analysis:

### 1. `trace_intermediate_calculations.py`
Requires trained TensorFlow model. Shows manual step-by-step calculations and compares with TensorFlow output.

```bash
source .venv/bin/activate
python3 model/trace_intermediate_calculations.py
```

### 2. `analyze_intermediate_values.py`
Works with saved weights/biases from COE files. Shows how values are calculated from exported FPGA data.

```bash
source .venv/bin/activate
python3 model/analyze_intermediate_values.py
```

## Key Takeaways

1. **Convolution** = sliding window multiply-sum-bias-relu operation
2. **Pooling** = simple max operation over non-overlapping windows
3. **Weights** are quantized to Q1.6 format and packed for efficient BRAM storage
4. **Each output value** involves many MAC operations (9 for Layer 0, 72 for Layer 2)
5. **Test pattern** is deterministic: `pixel[i,j] = (i+j+1) mod 256`
6. **VHDL must match** the exact calculation order and precision to get correct intermediate values
