# CNN Model Training and FPGA Export

This directory contains Python scripts for training a CNN model and exporting it for FPGA implementation.

## Prerequisites

### Python Requirements

- Python 3.8-3.11

# model — CNN training & FPGA export (short)

Minimal instructions to train the CNN and produce FPGA COE files.

## Prerequisites

- Python 3.8-3.11
- pip

Quick venv + install (Windows PowerShell):

```powershell
python -m venv .venv
venv\Scripts\Activate.ps1
pip install -r ../requirements.txt
```

Or, from Windows Command Prompt (cmd.exe):

```cmd
\.venv\Scripts\activate.bat   # or: \\venv\\Scripts\\activate.bat
```

Or (bash/mac):

```bash
python -m venv .venv
source .venv/bin/activate  # or: source venv/bin/activate
pip install -r ../requirements.txt
```

## Run training & export

Generates COE files in `model/fpga_weights_and_bias/` and `intermediate_values.npz`:

```bash
python model/CNN.py
```

## Notes

- Biases are packed: COE uses 1 address × (N_filters \* 8) bits (all biases in one wide word).
- Weights are organized per kernel position (depth = K_H×K_W, width = N_filters×8).

Vivado quick test (from repo root):

```powershell
vivado -mode batch -source scripts/create-project.tcl 2>&1 | Select-String -Pattern "^(?!#)"
```

## Quick troubleshooting

- Missing packages: `pip install tensorflow numpy`
- No training data: add `.npy` files to `model/training_data/`
- To reduce runtime: lower `EPOCHS` / `SAMPLES_PER_CLASS` in `CNN.py`

## Outputs

- `model/fpga_weights_and_bias/` — COE files for Vivado
- `intermediate_values.npz` — layer outputs for VHDL comparison
- `saved_model/`, `quantized_model.tflite` — model exports

That's all — run `python model/CNN.py` after activating the venv.

---

Updated: 2025-10-09
