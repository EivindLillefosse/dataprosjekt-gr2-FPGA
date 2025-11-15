#!/usr/bin/env bash
set -euo pipefail

# Run cnn_real_data_tb once (it performs two runs internally) without restarting Vivado,
# then run it again with isolation to emulate a restart. Save logs and artifacts.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

timestamp() { date +%Y%m%d_%H%M%S; }

TB="cnn_real_data_tb"
OUTDIR="test_runs"
mkdir -p "$OUTDIR"

run_one() {
    local mode_desc="$1"
    local env_vars="$2"
    local ts=$(timestamp)
    local run_dir="$OUTDIR/${TB}_${mode_desc}_$ts"
    mkdir -p "$run_dir"

    echo "Running $TB ($mode_desc) at $ts -> $run_dir"
    # Export environment variables (if any) and launch Vivado runner
    if [ -n "$env_vars" ]; then
        eval "$env_vars vivado -mode batch -source scripts/run-single-testbench.tcl -tclargs $TB" 2>&1 | grep -v '^#' | tee "$run_dir/${TB}.log"
    else
        vivado -mode batch -source scripts/run-single-testbench.tcl -tclargs "$TB" 2>&1 | grep -v '^#' | tee "$run_dir/${TB}.log"
    fi

    # copy recent summary report if present
    report_file=$(ls -t single_testbench_report_${TB}_*.log 2>/dev/null | head -n1 || true)
    if [ -n "$report_file" ]; then
        cp "$report_file" "$run_dir/"
    fi

    # copy xsim artifacts if produced
    sim_root="./vivado_project/CNN.sim/sim_1/behav/xsim"
    if [ -d "$sim_root" ]; then
        cp -r "$sim_root" "$run_dir/" 2>/dev/null || true
    fi

    # copy test image artifacts if available
    if [ -f src/test_images/test_image_pkg.vhd ]; then
        cp src/test_images/test_image_pkg.vhd "$run_dir/" || true
    fi
    if [ -f model/test_image_reference.npz ]; then
        cp model/test_image_reference.npz "$run_dir/" || true
    fi

    echo "Saved run artifacts to: $run_dir"
}

echo "Step 1: Run once without restart (cnn_real_data_tb performs two runs internally)"
run_one "no_restart" ""

echo "Step 2: Run again with restart/isolation (Vivado project will be reopened)"
# Use VIVADO_TEST_ISOLATE=1 to force the TCL runner to reopen/clean project
run_one "with_restart" "VIVADO_TEST_ISOLATE=1"

echo "All done. Check $OUTDIR for run folders."
