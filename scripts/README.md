README — Memory IP & Testbench helpers (short)

## Purpose

Quick reference for the automatic memory-IP creation and testbench scripts in this repo. The scripts discover .coe files, compute suitable Block RAM parameters, create Block Memory Generator IPs in Vivado, and help run testbenches.

## Quick commands

# Create project (auto-discover COEs and create IPs)

vivado -mode batch -source scripts/create-project.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive

# Create / regenerate only memory IPs (standalone)

vivado -mode batch -source scripts/create-memory-ips.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive

# Run testbenches (examples are in scripts/README_TESTBENCHES.md)

vivado -mode batch -source scripts/run-single-testbench.tcl -tclargs <testbench_entity> 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive

# Run all testbenches

vivado -mode batch -source ./scripts/run-all-testbenches.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive

## COE file requirements (minimal)

Each COE must include a small header with layer and shape information. Example (weights):

; Layer 0: conv2d weights (Q1.6 format)
; Original shape: (3, 3, 1, 8)
; Total elements: 72
;
memory_initialization_radix=16;
memory_initialization_vector=<hex_data>;

For biases use `; Shape: (N,)` instead of `Original shape:`.

## What the scripts do

- Search `model/fpga_weights_and_bias/`, `model/`, and project root for `*.coe` files.
- Parse layer number, shape and total elements from COE comments.
- Compute memory geometry:
  - Weights (K_H,K_W,C_in,N_filters): depth = K_H×K_W, width = N_filters×8 bits
  - Biases (N_filters,): depth = 1, width = N_filters×8 bits (all biases packed in one word)
- Create block memory IPs named `conv{L}_mem_weights` and `conv{L}_mem_bias` and set the COE as the init file.

## Memory layout (example: 3×3 kernel, 8 filters)

- `conv0_mem_weights`: 9 addresses × 64 bits (each 64-bit word packs 8×8-bit weights for that kernel position)
  - address = row \* 3 + col
  - douta(7 downto 0) = filter0 weight, douta(15 downto 8) = filter1, ..., douta(63 downto 56) = filter7
- `conv0_mem_bias`: 1 address × 64 bits (all 8 biases packed in one 64-bit word)
  - address = 0
  - douta(7 downto 0) = bias for filter0, douta(15 downto 8) = bias for filter1, ..., douta(63 downto 56) = bias for filter7

## VHDL usage snippet

COMPONENT conv0_mem_weights
PORT (
clka : IN STD_LOGIC;
ena : IN STD_LOGIC;
addra : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- log2(depth rounded up)
douta : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
);
END COMPONENT;

-- Example address: weight_addr <= std_logic_vector(to_unsigned(row \* 3 + col, 4));

## Troubleshooting (short)

- "No COE files found": make sure .coe files exist and script is run from `scripts/`.
- "Could not determine layer number": add `; Layer X:` to COE header.
- "No shape information found": add `; Original shape:` (weights) or `; Shape:` (biases).
- IP creation failures: check COE hex format, Vivado version, and disk space.

## Where to look for more

- `scripts/README_MEMORY_IPS.md` — full reference and examples
- `scripts/EXAMPLE_WORKFLOW.md` — step-by-step examples
- `scripts/README_TESTBENCHES.md` — testbench running tips and commands

## License / notes

COE files are the single source of truth for memory geometry. Regenerate IPs after retraining by updating COE files and running `create-memory-ips.tcl`.
