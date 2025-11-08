# Testing CNN with Real Google Quick Draw Data

This guide explains how to test the VHDL CNN implementation against real Google Quick Draw images instead of synthetic test patterns.

## Quick Start

### 1. Export a Real Quick Draw Image

```powershell
# Activate Python environment
.\.venv\Scripts\Activate.ps1

# Export a test image (e.g., airplane, sample 0)
python model/export_test_image.py --category airplane --index 0

# Or use first available category
python model/export_test_image.py --index 5

# See all available categories
python model/export_test_image.py --help
```

This generates:
- `src/test_images/test_image_pkg.vhd` - VHDL package with test image data
- `model/test_image.coe` - COE file for BRAM initialization (optional)
- `model/test_image_reference.npz` - Python reference for comparison
- `model/test_image_preview.png` - Visual preview of the test image

### 2. Update CNN Testbench

Modify `src/CNN/cnn_tb.vhd` to use the exported test image:

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;
use work.test_image_pkg.all;  -- ADD THIS LINE

-- In the architecture, replace the generate_test_image function:

-- OLD: Synthetic pattern
function generate_test_image return test_image_type is
    variable temp_image : test_image_type;
begin
    for row in 0 to IMAGE_SIZE-1 loop
        for col in 0 to IMAGE_SIZE-1 loop
            temp_image(row, col) := (row + col + 1) mod 256;
        end loop;
    end loop;
    return temp_image;
end function;

-- NEW: Real Quick Draw data
function generate_test_image return test_image_type is
    variable temp_image : test_image_type;
begin
    for row in 0 to IMAGE_SIZE-1 loop
        for col in 0 to IMAGE_SIZE-1 loop
            temp_image(row, col) := TEST_IMAGE_DATA(row, col);
        end loop;
    end loop;
    return temp_image;
end function;
```

### 3. Generate Python Reference with Same Image

Update `model/CNN.py` to use the same test image:

```python
# In capture_intermediate_values() function, replace create_test_image_28x28():

def create_test_image_28x28():
    """Load the SAME test image exported for VHDL"""
    ref_data = np.load('model/test_image_reference.npz')
    test_image = ref_data['image']
    category = str(ref_data['category'])
    category_idx = int(ref_data['category_idx'])
    print(f"Using exported test image: {category} (label {category_idx})")
    return test_image
```

### 4. Run Full Test Cycle

```powershell
# 1. Generate Python reference values with the same test image
python model/CNN.py

# 2. Run VHDL simulation
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs cnn

# 3. Compare VHDL output against Python reference
python model/debug_comparison.py `
    --vivado vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt `
    --npz model/intermediate_values.npz `
    --vhdl_scale 64 --vhdl_bits 8 `
    --layer layer_3_output
```

## Advanced Usage

### Testing Multiple Categories

Create a script to test all categories:

```powershell
# test_all_categories.ps1
$categories = @("airplane", "apple", "bicycle", "clock", "fish", "house", "moon", "pencil", "star", "tree")

foreach ($cat in $categories) {
    Write-Host "`n=== Testing category: $cat ===" -ForegroundColor Cyan
    
    # Export test image
    python model/export_test_image.py --category $cat --index 0 --no-viz
    
    # Generate Python reference
    python model/CNN.py
    
    # Run VHDL simulation
    vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs cnn
    
    # Compare results
    python model/debug_comparison.py `
        --vivado vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt `
        --npz model/intermediate_values.npz `
        --vhdl_scale 64 --vhdl_bits 8 `
        --layer layer_3_output
    
    # Archive results
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    New-Item -ItemType Directory -Force -Path "testbench_logs/category_tests/$cat"
    Copy-Item "vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt" `
              "testbench_logs/category_tests/$cat/${cat}_${timestamp}_debug.txt"
}
```

### Using MNIST Digits Instead

If you want to test with MNIST digits (handwritten 0-9):

```python
# Add to export_test_image.py:

def load_mnist_sample(index=0):
    """Load a MNIST digit sample."""
    from tensorflow.keras.datasets import mnist
    (x_train, y_train), (x_test, y_test) = mnist.load_data()
    
    # Use test set
    image = x_test[index]
    label = y_test[index]
    
    print(f"Loaded MNIST digit: {label}, sample {index}")
    return image, f"digit_{label}", int(label)

# Then use: --source mnist --index 42
```

## Verification Checklist

When testing with real data, verify:

- [ ] Test image preview shows recognizable drawing
- [ ] Python `intermediate_values.npz` contains correct layer shapes
- [ ] VHDL simulation completes without assertion failures
- [ ] Comparison shows reasonable error (avg error < 0.1 for Q1.6 outputs)
- [ ] Final classification matches expected category (check TEST_IMAGE_LABEL)

## Troubleshooting

### "No .npy files found"
- Ensure training data is downloaded: `model/training_data/*.npy`
- Check path matches: default is `model/training_data/`

### "Category not found"
- List available categories: `python model/export_test_image.py --help`
- Use exact spelling (case-sensitive)

### Large comparison errors
- Verify same test image used in Python and VHDL
- Check VHDL testbench loads `TEST_IMAGE_DATA` correctly
- Ensure Python normalization disabled (model trains on raw [0-255])

### VHDL compilation error: "test_image_pkg not found"
- Re-run export script to generate package
- Check package location: `src/test_images/test_image_pkg.vhd`
- Ensure TCL script includes `src/test_images/*.vhd` in project

## Expected Results

With real Quick Draw data:
- **Conv1 output**: Should show edge detection features
- **Pool1 output**: Downsampled feature maps (13×13)
- **Conv2 output**: Higher-level features (11×11)
- **Final output**: 5×5 feature maps for classification

Comparison statistics for correctly working design:
- **Average error (Q1.6)**: 0.01-0.1 (good), 0.1-0.2 (acceptable)
- **Zero filters**: Should be < 20% (most filters should activate)
- **Max error**: < 1.0 for most positions

## Integration with CI/CD

Add to automated testing:

```yaml
# .github/workflows/vivado_test.yml (example)
test_real_data:
  steps:
    - name: Export test image
      run: python model/export_test_image.py --category airplane --no-viz
    
    - name: Generate Python reference
      run: python model/CNN.py
    
    - name: Run VHDL simulation
      run: vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs cnn
    
    - name: Validate results
      run: |
        python model/debug_comparison.py \
          --vivado vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt \
          --npz model/intermediate_values.npz \
          --vhdl_scale 64 --vhdl_bits 8 \
          --layer layer_3_output \
          --max-error 0.2  # Fail if average error exceeds threshold
```

---

**Next Steps**: Try running the quick start sequence above with a real airplane drawing and compare the results!
