# Vivado Data Extraction Guide for CNN Debug Comparison

This guide explains how to extract simulation data from Vivado for use with the debug comparison tool.

## Method 1: VHDL File Output (Recommended)

### Step 1: Update Testbench

The testbench has been updated to write `intermediate_debug.txt` automatically.

### Step 2: Run Simulation

```tcl
# In Vivado TCL console
run_simulation
run 10ms
```

### Step 3: Locate Output File

The file `intermediate_debug.txt` will be created in your simulation directory:

- Usually: `vivado_project/CNN.sim/sim_1/behav/xsim/`
- Copy this file to your project root for the Python tool to find it

## Method 2: Export from Vivado Waveform

### Step 1: Run Simulation and Open Waveform

```tcl
run_simulation
open_wave_config simulation_waves.wcfg
run 10ms
```

### Step 2: Export Signal Data

1. In the waveform viewer, select the signals:

   - `input_pixel`, `input_valid`, `input_row`, `input_col`
   - `output_pixel`, `output_valid`, `output_row`, `output_col`

2. Right-click → "Export Wave Data"
3. Choose CSV format
4. Save as `simulation_data.csv`

### Step 3: Process with Python Tool

The debug comparison tool will automatically detect and parse the CSV file.

## Method 3: TCL Script Export

### Step 1: Source the Export Script

```tcl
# In Vivado TCL console after running simulation
source scripts/export_sim_data.tcl
```

### Step 2: Check Output Files

- `simulation_data.csv`: Raw signal data
- `transactions.csv`: Transaction-based data

## Method 4: Manual Log Analysis

### Step 1: Enable Report Statements

Make sure your testbench has report statements like:

```vhdl
report "Providing pixel [" & integer'image(row) & "," & integer'image(col) & "] = " & integer'image(value);
report "Output at position [" & integer'image(row) & "," & integer'image(col) & "]";
report "  Filter " & integer'image(i) & ": " & integer'image(result);
```

### Step 2: Capture Log Output

```tcl
# Run simulation with logging
run_simulation
run 10ms
# Log output will be in vivado.log or elaborate.log
```

### Step 3: Process Log File

The debug comparison tool can parse Vivado log files for report statements.

## File Locations

After simulation, look for data files in these locations:

1. **Project Root:**

   - `intermediate_debug.txt` (if file I/O works)
   - `simulation_data.csv` (if exported from waveform)

2. **Simulation Directory:**

   - `vivado_project/CNN.sim/sim_1/behav/xsim/intermediate_debug.txt`
   - `vivado_project/CNN.sim/sim_1/behav/xsim/elaborate.log`
   - `vivado_project/CNN.sim/sim_1/behav/xsim/simulate.log`

3. **Project Directory:**
   - `vivado.log`
   - `vivado.jou`

## Troubleshooting

### File I/O Not Working

If VHDL file I/O doesn't work:

1. Check file permissions
2. Use report statements instead
3. Export from waveform viewer
4. Use TCL script export

### No Data in Files

1. Verify simulation actually runs (check for layer_done signal)
2. Check that input_valid and output_valid signals are asserted
3. Verify testbench process are not stuck

### Parsing Errors

1. Check file format matches expected patterns
2. Verify signal names in CSV match expectations
3. Check for special characters in file paths

## Usage with Debug Tool

Once you have any of these files:

```bash
cd C:\Users\eivin\Documents\Skule\FPGA\dataprosjekt-gr2-FPGA
python model/debug_comparison.py
```

The tool will automatically detect and use available data files.
