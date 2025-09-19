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

| Parameter | Default Value |
|-----------|---------------|
| **Project Name** | `CNN` |
| **Project Directory** | `./vivado_project` |
| **Part Number** | `XC7A35TICSG324-1L` |
| **Top Module** | `top` |

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