Project: CNN FPGA (VHDL + Vivado)

These instructions give an AI coding assistant focused, actionable context for making safe edits and running tests in this repository.

## 1. Big-picture architecture

This is a VHDL-based CNN accelerator targeting Xilinx Artix-7 (7-series FPGAs). The design implements a modular CNN with:

- **CNN Pipeline**: Conv1 (28×28×1 → 26×26×8) → Pool1 (13×13×8) → Conv2 (13×13×8 → 11×11×16) → Pool2 (5×5×16)
- **Fixed-Point Arithmetic**: Q1.6 format (8-bit) for weights/activations, Q2.12 (16-bit) for MAC results
- **Memory**: Block RAM IPs store weights (MSB-first packing), bias constants in `bias_pkg.vhd`
- **Processing Model**: Time-multiplexed convolution (one MAC per filter, channels streamed sequentially)

### Key folders:

- `src/` — VHDL sources organized by component (CNN/, convolution_layer/, Max_pooling/, activation/, memory/, utility/)
- `src/utility/types.vhd` — Core type definitions: `WORD`, `WORD_ARRAY`, `WORD_ARRAY_16`
- `src/convolution_layer/bias_pkg.vhd` — Generated bias constants (layer_0_conv2d_BIAS, layer_2_conv2d_1_BIAS, etc.)
- `model/` — Python training scripts (`CNN.py`), quantization, COE file generation for BRAM initialization
- `scripts/` — TCL automation: `create-project.tcl`, `run-all-testbenches.tcl`, `create-memory-ips.tcl`
- `ip_repo/` — Generated Block Memory Generator IPs for weights/biases (auto-created from COE files)
- `vivado_project/` — Generated Vivado project (do not edit manually; regenerate with `create-project.tcl`)
- `testbench_logs/` — Simulation outputs, pass traces, error logs

## 2. Developer workflows (how to build/run/test)

### Model training and FPGA export (Python):

```powershell
# From repo root
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python model/CNN.py
```

This generates COE files in `model/fpga_weights_and_bias/` and `intermediate_values.npz` for verification.

### Create Vivado project:

```powershell
# Batch mode (discovers COE files, creates BRAM IPs, sets up project)
vivado -mode batch -source ./scripts/create-project.tcl

# Optional arguments: -tclargs <part_number> <top_module> <project_name>
# Shortcuts: -tclargs 35 (XC7A35T) or -tclargs 100 (XC7A100T)
```

### Run testbenches:

```powershell
# All testbenches
vivado -mode batch -source ./scripts/run-all-testbenches.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive

# Single testbench (entity name without _tb suffix)
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs <entity_name>

# Example: test MAC unit
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs MAC
```

Test artifacts: `testbench_logs/<test>_<timestamp>/` (simulator logs, `pass_trace.log`, `root_errors.log`, aggregated report)

### Environment variables for testing:

- `VIVADO_TEST_ISOLATE=1` — Re-open project for each test (fresh context, slower)
- `VIVADO_TEST_CLEAN=1` — Force clean simulation (delete xsim folders)
- `VIVADO_TEST_TIMEOUT_NS` — Override default simulation timeout (nanoseconds)

## 3. Project-specific conventions and patterns

### Type system (src/utility/types.vhd):

- `WORD` = `std_logic_vector(7 downto 0)` (8-bit Q1.6 format)
- `WORD_ARRAY` = `array (natural range <>) of WORD` (unconstrained, index `0 to N-1`)
- `OUTPUT_WORD` = `std_logic_vector(15 downto 0)` (16-bit Q2.12 MAC results)
- `WORD_ARRAY_16` = `array (natural range <>) of OUTPUT_WORD`
- **CRITICAL**: Always index arrays before type conversion: `signed(pixel_data(channel_index))` NOT `signed(pixel_data)`
- **CRITICAL**: Use nested aggregates for multi-dimensional initialization: `(others => (others => '0'))`

### Bias package (src/convolution_layer/bias_pkg.vhd):

- Generated from Python export, provides layer-specific bias constants
- `layer_0_conv2d_t` (8 filters), `layer_2_conv2d_1_t` (16 filters), `layer_5_dense_t` (64), `layer_6_dense_1_t` (10)
- Each element is `signed(7 downto 0)` in Q1.6 format
- **Usage pattern**: Declare local flexible array `type bias_local_t is array (natural range <>) of signed(7 downto 0)`, then use generate blocks to copy from package constants (see conv_layer_modular.vhd)

### LAYER_ID generic pattern:

- Used in `conv_layer_modular.vhd` and `weight_memory_controller.vhd`
- Selects layer-specific BRAM IP and bias constants at elaboration time using generate blocks
- Layer 0: `layer0_conv2d_weights` IP, `layer_0_conv2d_BIAS`
- Layer 1 (layer_2 in Python naming): `layer2_conv2d_1_weights` IP, `layer_2_conv2d_1_BIAS`
- **Pattern**: `gen_mem_0 : if LAYER_ID = 0 generate ... elsif LAYER_ID = 1 generate ...`
- **Validation**: Add elaboration-time assertions to check NUM_FILTERS matches bias array length

### Memory layout (BRAM packing):

- **Weights**: MSB-first packing. For N filters: `douta(W*N-1 downto W*(N-1))` = filter 0, `douta(W-1 downto 0)` = filter N-1
- **Address calculation**: `addr = ((kernel_row * K) + kernel_col) * C + channel` (K=kernel size, C=input channels)
- **Unpacking**: Use generate blocks: `weight_data(i) <= weight_dout(W*N-1-i*W downto W*N-(i+1)*W)`
- **Helper**: `clog2` function in weight_memory_controller.vhd computes address width

### File discovery and naming:

- Testbenches **MUST** end with `_tb.vhd` to be discovered by automation
- COE files **MUST** include header comments: `; Layer X:`, `; Original shape:` (weights) or `; Shape:` (biases)
- BRAM IPs auto-named: `layerX_conv2d_weights`, `layerX_conv2d_biases` (X from COE header)

### Single-driver accumulator pattern (UG901-like):

```vhdl
-- Synchronous sample of load/clear
process(clk)
begin
    if rising_edge(clk) then
        reg_load <= clear;
    end if;
end process;

-- Combinational feedback
old_result <= (others => '0') when reg_load = '1' else adder_out;

-- Single clocked process for pipeline
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            accumulator <= (others => '0');
        elsif compute_en = '1' then
            accumulator <= old_result + new_data;
        end if;
    end if;
end process;
```

See `src/utility/MAC/MAC.vhd` for canonical example.

### Start/done handshake:

- Many modules use `start` input pulse and `done` output pulse (single-cycle assertions)
- **Pattern**: Default outputs low each clock, assert in the specific cycle you want the agent to see the event
- **Synchronous**: Both start and done must be generated/sampled in clocked processes
- **Example**: Convolution controller FSM asserts `compute_clear` for one cycle, then `compute_en`, then waits for `compute_done`

### FSM controller pattern:

- **Two-process FSM**: Combinational `fsm_comb` (next-state logic) + synchronous `state_reg` (state transition)
- **Three-process outputs**: Combinational compute next-values (`v_output_valid`, etc.), synchronous `outputs_reg` to drive actual outputs
- **CRITICAL**: Do not read registered outputs in combinational logic (causes oscillation/latches)
- **Pattern**: `v_output_valid` computed in `fsm_comb`, sampled in `outputs_reg`, drives `output_valid` port
- See `src/convolution_layer/convolution_controller.vhd` for template

## 4. Common pitfalls to avoid

### Type errors:

- **Scalar vs. array**: `input_pixel` is `WORD_ARRAY(0 to C-1)`, not `WORD`. Use `input_pixel(0)` to access individual channels
- **Type conversion order**: Index first, then convert: `signed(weight_data(i))` NOT `signed(weight_data)(i)`
- **Generate block types**: Declare local flexible array types when copying from package constants with different sizes

### Signal initialization:

- **Never rely on X (uninitialized) behavior**. Initialize all signals explicitly: `signal reg_mult : signed(...) := (others=>'0');`
- **Reset logic**: Ensure all state/accumulator signals have synchronous reset branches

### Concurrent vs. sequential:

- **Illegal**: Concurrent `if`/`elsif` outside process (VRFC 10-91 error). Use generate blocks with `if`/`elsif` instead.
- **Single-driver rule**: Do not drive an output from both combinational and sequential processes
- **Solution**: Use `v_*` next-value signals in combinational, register them synchronously

### Pipeline timing:

- When changing MAC latency or convolution timing, update testbenches to wait for correct `done` timing
- **MAC latency**: Typically 1 cycle multiply + 1 cycle accumulate (2 total)
- **Convolution latency**: Kernel_size² × input_channels cycles per output pixel

### Testbench patterns:

- Initialize clock and reset correctly (reset active for 2-3 cycles minimum)
- Use `wait for <time>` NOT `wait until <condition>` for timeout safety
- Check `valid` signals before sampling outputs
- Match array sizes to DUT generics (`INPUT_CHANNELS`, `NUM_FILTERS`)

## 5. Important files to inspect when editing

### Core VHDL modules:

- `src/utility/types.vhd` — All custom types, read this first
- `src/convolution_layer/bias_pkg.vhd` — Generated bias constants (updated after retraining)
- `src/utility/MAC/MAC.vhd` — MAC timing, accumulator pattern, start/done handshake
- `src/convolution_layer/engine/convolution_engine.vhd` — MAC array, multi-channel pixel handling
- `src/convolution_layer/main/conv_layer_modular.vhd` — Top-level conv layer, integrates all subcomponents, generate block usage
- `src/convolution_layer/convolution_controller.vhd` — FSM template: combinational next-state + synchronous output registers
- `src/memory/weight_memory_controller.vhd` — BRAM wrapper, clog2 helper, LAYER_ID selection, MSB-first unpacking
- `src/CNN/cnn.vhd` — Top-level CNN, layer chaining, signal routing

### Automation scripts:

- `scripts/create-project.tcl` — Project creation, file discovery, BRAM IP generation
- `scripts/run-all-testbenches.tcl` — Batch test runner, environment variable handling
- `scripts/run-single-testbench.tcl` — Single test runner for quick iteration
- `scripts/create-memory-ips.tcl` — Standalone BRAM IP regeneration from COE files

### Python model:

- `model/CNN.py` — Training, quantization, COE export, intermediate value generation
- `model/fpga_weights_and_bias/` — Output COE files consumed by Vivado

### Testbenches (canonical examples):

- `src/utility/MAC/MAC_tb.vhd` — Basic MAC test with clear/accumulate
- `src/convolution_layer/engine/convolution_engine_tb.vhd` — Multi-channel convolution, array handling
- `src/memory/weight_memory_controller_tb.vhd` — LAYER_ID testing, address validation
- `src/CNN/cnn_tb.vhd` — Full pipeline integration test

## 6. How to run targeted checks locally (recommended quick loop)

### Fast iteration cycle:

1. Edit VHDL file
2. Run single testbench: `vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs <entity_name>`
3. Inspect `testbench_logs/<entity>_<timestamp>/simulate.log` for immediate failures
4. Check `root_errors.log` for assertion failures or runtime errors
5. If pass, run full test suite before commit

### Quick verification:

```powershell
# Check syntax/elaboration only (no simulation)
vivado -mode batch -source scripts/create-project.tcl  # Recreates project, checks compile order

# Run subset of tests (e.g., all MAC tests)
vivado -mode batch -source ./scripts/run-all-testbenches.tcl -tclargs MAC
```

### Debugging tips:

- Use `report` statements in VHDL for runtime debug: `report "Value: " & integer'image(my_signal) severity note;`
- Enable waveform capture in testbench: `open_wave_config`, `log_wave`, `add_wave`
- Check compile order: scripts use `update_compile_order` to handle packages first
- **Type errors**: Read the VRFC error message carefully, it usually points to the exact line and type mismatch

## 7. When to open a PR vs. direct edits

### Direct commits to feature branch:

- Small, local-only fixes to testbenches (typos, timing adjustments)
- Single-file timing adjustments (e.g., wait statement changes)
- Documentation updates

### PR required:

- Design or API changes (interfaces, generics, signal polarity)
- New components or modules
- Changes affecting multiple files or modules
- Modifications to memory layout, type definitions, or bias_pkg
- **MUST include**: Updated testbenches and passing test run artifacts in `testbench_logs/`

### Before submitting PR:

1. Run full testbench suite: `vivado -mode batch -source ./scripts/run-all-testbenches.tcl`
2. Check `testbench_logs/` for any failures
3. Commit test logs with PR (shows evidence of testing)
4. Update README or this file if adding new conventions

## 8. Python model workflow

### Training and export:

```powershell
cd model
python CNN.py
```

This generates:

- `fpga_weights_and_bias/*.coe` — BRAM initialization files
- `intermediate_values.npz` — Layer outputs for VHDL verification
- `saved_model/`, `quantized_model.tflite` — TensorFlow artifacts

### COE file format (required header):

```coe
; Layer 0: conv2d weights (Q1.6 format)
; Original shape: (3, 3, 1, 8)
; Total elements: 72
;
memory_initialization_radix=16;
memory_initialization_vector=<hex_data>;
```

### Regenerate BRAM IPs after retraining:

```powershell
# Update COE files, then:
vivado -mode batch -source scripts/create-memory-ips.tcl

# Or recreate entire project (includes IP regeneration):
vivado -mode batch -source scripts/create-project.tcl
```

## 9. If you need more info

### Ask maintainer for:

- Vivado version (tested with 2024.1, version compatibility critical)
- Target part used in nightly runs (default: XC7A35TICSG324-1L)
- Status of CI/CD pipeline (if applicable)
- Specific layer timing requirements or resource constraints

### Useful Xilinx documentation:

- UG901 (Vivado Synthesis Guide) — Single-driver patterns, accumulator design
- UG953 (Vivado Design Suite Tcl Command Reference) — TCL scripting
- PG058 (Block Memory Generator) — BRAM IP configuration

### Debug resources:

- `testbench_logs/<test>_<timestamp>/simulate.log` — Full simulation transcript
- `testbench_logs/<test>_<timestamp>/root_errors.log` — Aggregated errors/assertions
- Vivado GUI: Open `vivado_project/CNN.xpr` for interactive debug (waveforms, elaborated design browser)

## Verifying VHDL outputs vs Python (quick guide)

Use the included comparison script `model/debug_comparison.py` to compare intermediate VHDL simulation outputs with the Python reference outputs generated by `model/CNN.py`.

1. Generate Python reference data (if you haven't already):

```powershell
# from repo root, using the project's venv
venv\Scripts\Activate.ps1
python model/CNN.py
```

This writes `model/intermediate_values.npz` and also emits COE files under `model/fpga_weights_and_bias/`.

2. Run the Vivado simulation that emits the debug file `modular_intermediate_debug.txt` (testbenches do this automatically when enabled). The file lives under `vivado_project/CNN.sim/sim_1/behav/xsim/`.

3. Run the comparison script. Example usages:

```powershell
# Compare Python layer_0_output against VHDL 'MODULAR_OUTPUT' blocks (map them to vhdl_layer 'final')
python model/debug_comparison.py \
    --vivado vivado_project\CNN.sim\sim_1\behav\xsim\modular_intermediate_debug.txt \
    --npz model\intermediate_values.npz \
    --vhdl_scale 64 --vhdl_bits 8 \
    --layer layer_0_output --vhdl_layer final

# Compare Pool1 (layer_1_output) mapping same MODULAR_OUTPUT entries
python model/debug_comparison.py --vivado <path-to-debug> --npz model\intermediate_values.npz --layer layer_1_output --vhdl_layer final
```

Key flags:

- `--vhdl_scale`: scale factor used by VHDL outputs (64 for Q1.6). If VHDL reports raw MAC outputs, try larger values (e.g. 4096).
- `--vhdl_bits`: bit-width of the VHDL reported value (8 for post-scaled Q1.6 outputs, 16 for raw MAC accumulator values).
- `--layer`: Python layer key (for example `layer_0_output`, `layer_1_output`, `layer_2_output`). The script prints available keys when loading the NPZ.
- `--vhdl_layer`: optional explicit VHDL layer type to filter (e.g. `final`, `layer0`, `layer1`, `layer2`) — useful when the TB emits `MODULAR_OUTPUT` entries which are parsed as type `final`.

Interpreting results:

- The script prints per-position per-filter comparisons and overall statistics (average error, max error, per-filter zero counts).
- Average error < 0.01: excellent. < 0.05: good. 0.05–0.2: moderate — investigate scaling/bias. > 0.2: poor — check addressing, memory packing, or wrong test image.
- If many filters show 100% zeros, inspect weight COE files (`model/fpga_weights_and_bias/`) and the BRAM unpacking logic in `src/memory/weight_memory_controller.vhd`.

Quick troubleshooting checklist:

- Ensure `model/intermediate_values.npz` was generated from the same input image used in the VHDL testbench. Mismatched inputs cause large errors.
- If outputs look shifted or systematically off, compare bias arrays in `src/convolution_layer/bias_pkg.vhd` against `model/fpga_weights_and_bias/*biases.coe`.
- If specific filters are always zero: verify COE content and BRAM packing convention (MSB-first). Check `weight_memory_controller.vhd` unpacking lines and `clog2` address math.
- If VHDL printed `MODULAR_OUTPUT` but the script found 0 entries for your chosen layer, use `--vhdl_layer final` to include those entries.

If you'd like, I can add a small helper script to automatically run comparisons for all conv/pool layers and produce a short summary report.
