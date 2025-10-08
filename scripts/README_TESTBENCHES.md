# Testbench Execution Scripts

This directory contains scripts for running VHDL testbenches in Vivado:

## Run All Testbenches (Sequential)

Run all testbenches one at a time (recommended for Windows):

```pwsh
vivado -mode batch -source ./scripts/run-all-testbenches.tcl 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive
```

## Run All Testbenches (Parallel, Experimental)

Run multiple testbenches in parallel (Linux/Unix or powerful Windows systems):

```pwsh
vivado -mode batch -source ./scripts/run-all-testbenches-parallel.tcl -tclargs <jobs> 2>&1 | Select-String -Pattern "^(?!#)" -CaseSensitive
```

Replace `<jobs>` with number of parallel jobs (e.g., 2, 4, 8).

## Run a Single Testbench

Run one testbench by entity name:

```pwsh
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs <testbench_entity>
```

Example:

```pwsh
vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs relu_layer_tb
```

## Recommendations

- Use sequential script for reliability on Windows
- Use parallel script only if you have enough RAM/CPU
- Use single-testbench script for debugging or individual runs

## Output

Scripts generate timestamped log files in `testbench_logs/`.
