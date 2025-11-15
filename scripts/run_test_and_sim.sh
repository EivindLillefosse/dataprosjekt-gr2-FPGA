#!/usr/bin/env bash
# Generate a test image and run the cnn_clean_tb simulation using the project's
# run-single-testbench.tcl helper. Saves logs, the Vivado summary report and the
# generated image artifacts into a timestamped directory under ./test_runs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="$ROOT/.venv/bin/python"
if [ ! -x "$PY" ]; then
    PY=python
fi

# Testbench entity to run (default cnn_clean_tb)
TB="${1:-cnn_clean_tb}"
OUTBASE="${2:-test_runs}"
mkdir -p "$OUTBASE"

# Default tests: two different indices of the same category so you can compare
# Change or pass tests as additional args in the form category:index
DEFAULT_TESTS=("banana:0" "banana:1")
shift 2 2>/dev/null || true
if [ "$#" -gt 0 ]; then
    TESTS=("$@")
else
    TESTS=("${DEFAULT_TESTS[@]}")
fi

timestamp() { date +%Y%m%d_%H%M%S; }

for t in "${TESTS[@]}"; do
    IFS=':' read -r category index <<< "$t"
    echo "\n=== Test: category=$category index=$index (generated at $(timestamp)) ==="

    echo "Generating test image with Python exporter..."
    "$PY" model/export_test_image.py --source quickdraw --category "$category" --index "$index" --no-viz

    run_ts=$(timestamp)
    run_dir="$OUTBASE/${TB}_${category}_${index}_$run_ts"
    mkdir -p "$run_dir"

    echo "Running Vivado simulation for testbench '$TB'..."
    # Run Vivado with the project's single-testbench runner. Filter out lines that start with '#'
    vivado -mode batch -source scripts/run-single-testbench.tcl -tclargs "$TB" 2>&1 | grep -v '^#' | tee "$run_dir/${TB}_${category}_${index}.log"
    vivado_rc=${PIPESTATUS[0]}

    # Copy the runner summary report (if present)
    report_file=$(ls -t single_testbench_report_${TB}_*.log 2>/dev/null | head -n1 || true)
    if [ -n "$report_file" ]; then
        cp "$report_file" "$run_dir/"
    fi

    # Copy generated image artifacts so the run is self-contained
    if [ -f src/test_images/test_image_pkg.vhd ]; then
        cp src/test_images/test_image_pkg.vhd "$run_dir/test_image_pkg_${category}_${index}.vhd"
    fi
    if [ -f model/test_image_reference.npz ]; then
        cp model/test_image_reference.npz "$run_dir/test_image_reference_${category}_${index}.npz"
    fi
    if [ -f "model/test_image_bytes_${category}.txt" ]; then
        cp "model/test_image_bytes_${category}.txt" "$run_dir/test_image_bytes_${category}_${index}.txt"
    fi

    echo "Run artifacts saved to: $run_dir"
    if [ $vivado_rc -ne 0 ]; then
        echo "Vivado returned non-zero exit code: $vivado_rc. See logs in $run_dir"
    fi
done

echo "\nAll done."
