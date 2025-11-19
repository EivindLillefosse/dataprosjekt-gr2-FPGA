 # CNN FPGA Implementation

This repository contains a Convolutional Neural Network (CNN) implemented in VHDL
and supporting Python tools for training, quantization and exporting weights for
FPGA deployment. The project targets Xilinx Artix-7 devices and includes automation
scripts for Vivado project creation and simulation.

- Workspace root: project scripts, constraints, IP, VHDL sources, and model helpers

## Layout (important folders)

- `src/` — VHDL sources and testbenches. Keep testbenches named with `_tb.vhd`.
- `constraints/` — XDC files for timing and pin assignments (dev vs pcb variants present).
- `ip_repo/` — local IP wrappers and XDCs (clock-wiz, BRAM blocks, etc.).
- `model/` — Python model training, intermediate-value capture, and FPGA export helpers.
- `scripts/` — TCL scripts used by Vivado for project creation and running simulations.
- `vivado_project/` — generated Vivado project files (usually ignored in version control).

## Quick Commands

Open a PowerShell with Vivado in PATH.

Create project (batch):

```powershell
vivado -mode batch -source ./scripts/create-project.tcl
```

Run all testbenches (batch):

```powershell
vivado -mode batch -source ./scripts/run-all-testbenches.tcl 2>&1 | Select-String -Pattern '^[^#]' -CaseSensitive
```

Run a single testbench (batch):

```powershell
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs <entity_name>
```

If you prefer interactive Vivado GUI, use `vivado` (no arguments) and open `vivado_project`.

## Model & FPGA export (Python)

The `model/CNN.py` script trains or loads a Keras model, captures intermediate layer data for
VHDL testbench comparison, and exports quantized weights/biases to COE files used by BRAMs.

Important defaults used by the export pipeline:

- Fixed-point format: Q1.6 (1 integer bit + 6 fractional bits)
- Scale factor: 64 (weights are multiplied by 64 and rounded to signed int8)
- Value clamp range: [-2.0, 1.984375]

To run the Python pipeline (training + export):

```powershell
# create a Python venv, activate it, and install requirements
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt  # or install tensorflow, numpy, sklearn, matplotlib, seaborn

# train and export
python model/CNN.py
```

To run only the test/capture steps using an existing SavedModel:

```powershell
python model/CNN.py --only-tests --model-path model/saved_model
```

The export writes COE files to `model/fpga_weights_and_bias/` and also attempts to write a
VHDL bias package to `src/convolution_layer/bias_pkg.vhd` for convenience.

## Notes & Troubleshooting

- IP-generated XDCs (clock-wiz, etc.) can create duplicate `create_clock` constraints.
  Prefer a single top-level `create_clock` and add `create_generated_clock` mappings
  for derived clocks. Some IP XDCs in `ip_repo/` were adjusted to avoid conflicts.

- The VHDL is written to treat weight/bias bytes as signed Q1.6 values; ensure any
  testbench or Python dequantization uses `/64.0` to obtain floating-point equivalents.

- If Vivado reports parameter lookup errors for IPs (e.g., missing `CLOCK_*` keys),
  check `scripts/ip_manifests/` for the IP manifest used by any automation and ensure
  required keys are present.