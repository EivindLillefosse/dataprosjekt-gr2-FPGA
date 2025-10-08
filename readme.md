# CNN FPGA Implementation

This project implements a Convolutional Neural Network (CNN) on FPGA using VHDL. The design targets Xilinx 7-series FPGAs and includes modular components for convolution operations, MAC units, and SPI communication.

## Prerequisites

- Ensure that Vivado is added to your environment variables
- Xilinx Vivado 2024.1 or compatible version
- Target FPGA: Artix-7 (XC7A35T or XC7A100T)

## Quick Start

### Basic Project Creation

Run the following command from the Git repository folder to generate a local project in batch mode:

```bash
vivado -mode batch -source ./scripts/create-project.tcl
```

### Advanced Usage

The script supports optional command-line parameters for flexibility:

```bash
vivado -mode batch -source ./scripts/create-project.tcl -tclargs [part_number] [top_module] [project_name]
```

#### Examples

```bash
# Use XC7A100T FPGA
vivado -mode batch -source ./scripts/create-project.tcl -tclargs 100

# Custom configuration
vivado -mode batch -source ./scripts/create-project.tcl -tclargs XC7A100TCSG324-1 my_top MyProject

# Quick part selection using shortcuts
vivado -mode batch -source ./scripts/create-project.tcl -tclargs 35    # XC7A35TICSG324-1L
vivado -mode batch -source ./scripts/create-project.tcl -tclargs 100   # XC7A100TCSG324-1
```

### Default Configuration

| Parameter             | Default Value       |
| --------------------- | ------------------- |
| **Project Name**      | `CNN`               |
| **Project Directory** | `./vivado_project`  |
| **Part Number**       | `XC7A35TICSG324-1L` |
| **Top Module**        | `top`               |

## Project Structure

```
├── src/                          # VHDL source files
│   ├── top.vhd                   # Top-level entity
│   ├── types.vhd                 # Custom type definitions
│   ├── module_folders/           # Organized component modules
│   │   ├── submodules/           # Nested subcomponents
│   │   ├── *.vhd                 # Module implementations
│   │   └── *_tb.vhd              # Corresponding testbenches
│   └── *_tb.vhd                  # Top-level testbenches
├── constraints/                  # Timing and pin constraints
│   └── *.xdc                     # Constraint files
├── scripts/                      # Automation scripts
│   ├── create-project.tcl        # Project setup automation
│   └── run-sim.tcl               # Simulation runner
├── model/                        # Reference models and docs
└── vivado_project/               # Generated Vivado files
```

## Features

- **Modular Design**: Hierarchical VHDL components for easy maintenance
- **Automated Project Setup**: TCL scripts for rapid project creation
- **Comprehensive Testbenches**: All modules include corresponding testbenches
- **Multi-FPGA Support**: Configurable for different Artix-7 variants
- **SPI Interface**: Communication interface for external data exchange

## Design Notes

- The file structure in the `src` directory can be up to two folders deep
- All testbenches must have filenames ending with `_tb.vhd`
- The script automatically adds VHDL source files (excluding testbenches) and constraint files
- Testbench files are automatically added to the simulation fileset

## Block Diagram

Below is the high-level block diagram for the project:

![Block Diagram](model/Block-diagram.svg)

## SPI Design Choices

The SPI slave module in this project is designed for flexibility and reliability in FPGA-to-MCU communication. Key choices and features:

- **SPI Mode 0 (CPOL=0, CPHA=0):**
  - Data is sampled on the rising edge of SCLK and shifted out on the falling edge.
  - SCLK idles low; slave select (SS_N) is active low.
- **Generic Data Length:**
  - The module uses a `DATA_LENGTH` generic, allowing you to set the SPI word size (default is 8 bits, but any length is supported).
  - All internal logic and testbenches adapt automatically to the chosen data length.
- **Synchronized SPI Signals:**
  - All SPI signals are synchronized to the FPGA system clock for safe and robust operation.
  - Edge detection is performed in the clock domain to avoid metastability.
- **Acknowledge and Data Valid:**
  - The module provides `ack` and `data_valid` outputs, which pulse high for one clock after each complete word transfer.
- **Minimal, Portable Testbench:**
  - The testbench is simple, parameterized, and sends/receives multiple words to verify correct operation for any data length.

This approach ensures the SPI interface is both easy to use and adaptable to a wide range of applications and word sizes.

## Testbench Automation & Simulation Workflow

Extensive TCL automation is provided to run either the full suite of testbenches or a single testbench with rich logging, error classification, and optional isolation.

### Run All Testbenches (Sequential)

```
vivado -mode batch -source ./scripts/run-all-testbenches.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive
```

Key features:

- Automatic discovery of all files matching `*_tb.vhd` anywhere under `./src`
- Per‑test result classification: PASS / FAIL / SKIP
- Log delta scanning (only new lines since previous test) across `vivado.log` and project `.log` files
- Error categorization: Assertion, Compile (xvhdl/xvlog/xelab), Simulation, Other
- Per‑test artifact directory: `testbench_logs/<test>_<timestamp>/` containing:
  - `root_errors.log` (or `pass_trace.log` for passes)
  - Copied raw simulator logs (`elaborate.log`, `simulate.log`, `xvhdl.log`, etc.)
  - `error_summary.log` with contextual (prev/next line) excerpts
- Final aggregated report: `testbench_report_<timestamp>.log`

### Environment Controls (Optional)

| Variable                 | Value      | Effect                                                                          |
| ------------------------ | ---------- | ------------------------------------------------------------------------------- |
| `VIVADO_TEST_ISOLATE`    | `1`        | Re-opens the Vivado project before every test (fresh context)                   |
| `VIVADO_TEST_CLEAN`      | `1`        | Deletes the `xsim` simulation directory and forces `-clean` simulation per test |
| `VIVADO_TEST_TIMEOUT_NS` | integer ns | Overrides default 30,000,000 ns run timeout                                     |

PowerShell example enabling isolation & clean:

```
$env:VIVADO_TEST_ISOLATE="1"; $env:VIVADO_TEST_CLEAN="1"; vivado -mode batch -source ./scripts/run-all-testbenches.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive
```

### Run a Single Testbench

Use the dedicated script for faster iteration:

```
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs <entity_name>
```

Examples:

```
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs top_tb
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs conv_layer_modular_tb
$env:VIVADO_TEST_CLEAN="1"; vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs weight_memory_controller_tb
```

Outputs:

- `single_testbench_report_<entity>_<timestamp>.log`
- `testbench_logs/<entity>_<timestamp>/` (same structure as multi-run)

### Interpreting Error Classification

| Category  | Meaning                                                | Typical Root Causes                                                           |
| --------- | ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| Assertion | Testbench or design `assert` triggered                 | Wrong expected data, timing, handshake mismatch                               |
| Compile   | Parsing/elaboration errors (`xvhdl`, `xvlog`, `xelab`) | Missing file, order dependency, unbound component, package not compiled first |
| Sim       | Runtime simulation issues (`xsim`)                     | Access to uninitialized signals, fatal conditions                             |
| Other     | Anything else matched (generic `ERROR:` / `FATAL:`)    | Tool internal errors or unclassified messages                                 |

### Typical Failure: `[Common 17-39] 'launch_simulation' failed due to earlier errors.`

This is a wrapper message. Look inside:

1. `testbench_logs/<test>_<timestamp>/root_errors.log`
2. `error_summary.log` for the first underlying compile/elab message.

Common fixes:

- Ensure `types.vhd` (packages) are compiled before dependents (automation already calls `update_compile_order`).
- For generated memory/IP modules, confirm their simulation sources are added to `sim_1` fileset.
- Remove stale simulation artifacts (`VIVADO_TEST_CLEAN=1`).
- Use isolation (`VIVADO_TEST_ISOLATE=1`) when state leakage between tests is suspected.

### Reducing Noise

- Filtering pipeline (`Select-String -Pattern "^(?!#)"`) removes echoed commented lines from Vivado batch output.
- Pass logs can be pruned by deleting their directories if storage is a concern; adjust script if you wish to suppress pass traces entirely.

### Adding New Testbenches

1. Create `your_module_tb.vhd` in the same (or a sub) directory under `src/`.
2. Ensure entity name matches filename root (`your_module_tb`).
3. Re-run the multi-test script; discovery is automatic.

### Quick Debug Loop

1. Run single test: `run-single-testbench.tcl`.
2. Inspect `root_errors.log` & waveform (launch GUI if needed after batch creation).
3. Iterate design/testbench.
4. Run full suite before commit to ensure no cross-test regressions.

### Troubleshooting Checklist

- No tests found: Confirm filenames end with `_tb.vhd` and reside under `./src`.
- All tests failing instantly: Project not created — run `create-project.tcl` first.
- Intermittent failures only in batch mode: enable isolation & clean env vars.
- Assertions only when run after another test: potential shared resource or uninitialized signal; add reset logic in TB.
- Large vivado.log producing false positives: refine regex inside scripts (look for additional tokens) — current defaults focus on `ERROR:` / `FATAL:` / assertion text.

### Future Enhancements (Ideas)

- Optional JUnit/XML export for CI systems.
- Waveform capture toggle (e.g., `VIVADO_TEST_WAVES=1`).
- Parallel safe execution (currently experimental on Windows due to result file race conditions).

---

If you modify or extend the automation, keep naming consistent and prefer incremental log scanning to avoid re-processing large logs for every test.
