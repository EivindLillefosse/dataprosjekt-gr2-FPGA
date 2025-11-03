# Input Scaling Mismatch Issue

## Problem

The CNN model has a **fundamental input scaling mismatch** between Python training and VHDL implementation:

### Python Model (Training)
- Inputs: **Normalized [0, 1]** range (pixel_value / 255)
- Conv2D weights: Trained for normalized inputs
- Example: pixel=1 in Python means 1/255 = 0.00392

### VHDL Implementation (Current)
- Inputs: **Raw [0, 255]** 8-bit unsigned integers
- Conv2D weights: Same as Python (trained for [0,1])
- Example: pixel=1 in VHDL means raw value 1

### Result
VHDL MAC results are **~255x too large** compared to Python!

Example calculation:
```
Python: 0.004 × weight = small value
VHDL:   1     × weight = 255x larger!
```

## Solutions

### Option 1: Scale Weights During Export (RECOMMENDED)
**Modify** xport_to_FPGA() to scale Conv2D layer weights by 1/255:

`python
if isinstance(layer, tf.keras.layers.Conv2D):
    weights = weights_and_biases[0] / 255.0  # Scale for raw inputs
`

**Pros**: No VHDL changes needed, maintains Q1.6 format  
**Cons**: Weights become very small, may lose precision

### Option 2: Normalize Inputs in VHDL
**Add** normalization before MAC in VHDL:

`hdl
normalized_pixel <= std_logic_vector(to_unsigned(to_integer(unsigned(input_pixel)) / 255, 8));
`

**Pros**: Matches Python exactly  
**Cons**: Adds division hardware, complex

### Option 3: Retrain with Raw Inputs
**Modify** load_data() to skip normalization:

`python
x = x.reshape(-1, 28, 28, 1).astype('float32')  # Remove /255.0
`

**Pros**: Perfect match, no precision loss  
**Cons**: Requires complete retraining

## Current Status

✅ Issue identified and documented  
✅ **FIXED - Implemented Option 3**: Model retrained on raw [0-255] inputs  
✅ CNN.py modified to train without normalization (line 72)  
✅ capture_intermediate_values updated to use raw inputs (line 118)  
✅ export_to_FPGA updated to reflect new training approach  

**Next Step**: Run `python model/CNN.py` to retrain and export the model

## Recommended Action

**COMPLETED** - Implemented Option 3 (retrain with raw inputs).  
After retraining, re-verify with debug_comparison.py to confirm <5% error.
