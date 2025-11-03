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
  # CNN FPGA Implementation

  ![Workflow](https://img.shields.io/badge/workflow-vivado-blue) ![License: MIT](https://img.shields.io/badge/license-MIT-green)

  This repository contains a VHDL implementation of a Convolutional Neural Network (CNN) targeting Xilinx 7-series (Artix-7) FPGAs. It uses modular VHDL components for convolution, MAC units, SPI communication and provides TCL automation to create projects and run simulations.

  ## Table of contents
  - [Prerequisites](#prerequisites)
  - [Quick start](#quick-start)
  - [Project structure](#project-structure)
  - [Testing & automation](#testing--automation)
  - [Troubleshooting](#troubleshooting)
  - [Contributing](#contributing)

  ## Prerequisites

  - Xilinx Vivado (2024.1 recommended, but compatible versions should work)
  - Vivado in PATH (so `vivado` command is available)
  - Target FPGA families: Artix-7 (e.g. XC7A35T, XC7A100T)

  ## Quick start

  Create the Vivado project (batch mode):

  ```powershell
  vivado -mode batch -source ./scripts/create-project.tcl
  ```

  Create with custom arguments:

  ```powershell
  vivado -mode batch -source ./scripts/create-project.tcl -tclargs <part_number> <top_module> <project_name>
  ```

  Examples:

  ```powershell
  # Use XC7A100T
  vivado -mode batch -source ./scripts/create-project.tcl -tclargs 100

  # Custom config
  vivado -mode batch -source ./scripts/create-project.tcl -tclargs XC7A100TCSG324-1 top MyProject
  ```

  ### Default configuration

  | Parameter | Default |
  |---|---|
  | Project name | `CNN` |
  | Project dir | `./vivado_project` |
  | Part number | `XC7A35TICSG324-1L` |
  | Top module | `top` |

  ## Project structure

  Top-level layout:

  ```
  src/                 # VHDL sources and testbenches
  constraints/         # XDC constraint files
  scripts/             # TCL automation (project creation, tests)
  model/               # Reference models (.py/.onnx/.tflite) and diagrams
  vivado_project/      # Generated Vivado project files (ignored in VCS)
  testbench_logs/      # Simulation artifacts produced by test scripts
  ```

  Testbenches must end with `_tb.vhd` to be discovered by the automation.

  ## Testing & automation

  Run all testbenches (PowerShell):

  ```powershell
  vivado -mode batch -source ./scripts/run-all-testbenches.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive
  ```

  Run a single testbench:

  ```powershell
  vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs <entity_name>
  ```

  Environment variables supported by the test scripts:

  - `VIVADO_TEST_ISOLATE=1` — re-open project for every test (fresh context)
  - `VIVADO_TEST_CLEAN=1` — delete `xsim` folders and force clean simulation
  - `VIVADO_TEST_TIMEOUT_NS` — override default simulation timeout (ns)

  Output artifacts are placed under `testbench_logs/<test>_<timestamp>/` and include `root_errors.log`, simulator logs and an aggregated report like `single_testbench_report_<entity>_<timestamp>.log`.

  ## Troubleshooting

  - No tests found: ensure filenames end with `_tb.vhd` and exist under `src/`.
  - All tests fail immediately: run `create-project.tcl` first to ensure project exists.
  - Common simulation failure: inspect `testbench_logs/<test>_<timestamp>/root_errors.log` and `error_summary.log`.
  - Vivado command not found: ensure Vivado bin is on PATH and restart the terminal/VS Code.

  ## Contributing

  1. Create a feature branch.
  2. Add tests (or update existing testbenches) for any behavior changes.
  3. Run the testbench scripts locally and ensure tests pass.
  4. Open a pull request with a clear description.

  ## Notes

  - Keep testbench filenames consistent (`*_tb.vhd`).
  - The automation already attempts to compile packages first (uses `update_compile_order`), but if you add new packages, ensure dependent files compile in the correct order.

  ---

  If you'd like, I can also:

  - Add a `LICENSE` file (MIT) and a short `CONTRIBUTING.md`.
  - Generate a short `Makefile` or PowerShell script to wrap common Vivado calls.
