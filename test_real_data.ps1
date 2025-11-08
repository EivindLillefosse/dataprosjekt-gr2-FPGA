# Test CNN with Real Quick Draw Data - Automated Script
# Usage: .\test_real_data.ps1 -Category apple -Index 0

param(
    [string]$Category = "apple",
    [int]$Index = 0,
    [switch]$SkipVivado,
    [switch]$SkipPython
)

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "CNN Real Data Test - Category: $Category, Sample: $Index" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# Step 1: Export test image from Quick Draw dataset
Write-Host "`n[1/4] Exporting test image..." -ForegroundColor Yellow
python model/export_test_image.py --category $Category --index $Index --no-viz
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to export test image" -ForegroundColor Red
    exit 1
}

# Step 2: Generate Python reference values with same image
if (-not $SkipPython) {
    Write-Host "`n[2/4] Generating Python reference values..." -ForegroundColor Yellow
    
    # Create temporary modified CNN.py that loads the exported test image
    $cnnScript = Get-Content "model/CNN.py" -Raw
    
    # Check if we need to modify the test image loading
    if ($cnnScript -notmatch "test_image_reference.npz") {
        Write-Host "⚠️  CNN.py needs manual update to load exported test image" -ForegroundColor Yellow
        Write-Host "   Add to capture_intermediate_values():" -ForegroundColor Yellow
        Write-Host "   ref_data = np.load('model/test_image_reference.npz')" -ForegroundColor Yellow
        Write-Host "   test_image = ref_data['image']" -ForegroundColor Yellow
        Write-Host "`n   Continuing with current CNN.py..." -ForegroundColor Yellow
    }
    
    python model/CNN.py
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to generate Python reference" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "`n[2/4] Skipping Python reference generation" -ForegroundColor Gray
}

# Step 3: Run VHDL simulation
if (-not $SkipVivado) {
    Write-Host "`n[3/4] Running VHDL simulation..." -ForegroundColor Yellow
    Write-Host "   (This may take several minutes...)" -ForegroundColor Gray
    
    vivado -mode batch -source scripts/run-single-testbench.tcl -tclargs cnn 2>&1 | 
        Select-String -Pattern "^(?!#)" -CaseSensitive
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: VHDL simulation failed" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "`n[3/4] Skipping VHDL simulation" -ForegroundColor Gray
}

# Step 4: Compare results
Write-Host "`n[4/4] Comparing VHDL output against Python reference..." -ForegroundColor Yellow

$debugFile = "vivado_project/CNN.sim/sim_1/behav/xsim/cnn_intermediate_debug.txt"
if (Test-Path $debugFile) {
    # Try both Q1.6 (8-bit scaled) and Q2.12 (16-bit raw) formats
    
    Write-Host "`n--- Q1.6 Format (8-bit, scale=64) ---" -ForegroundColor Cyan
    python model/debug_comparison.py `
        --vivado $debugFile `
        --npz model/intermediate_values.npz `
        --vhdl_scale 64 --vhdl_bits 8 `
        --layer layer_3_output
    
    Write-Host "`n--- Q2.12 Format (16-bit, scale=4096) ---" -ForegroundColor Cyan
    python model/debug_comparison.py `
        --vivado $debugFile `
        --npz model/intermediate_values.npz `
        --vhdl_scale 4096 --vhdl_bits 16 `
        --layer layer_3_output
} else {
    Write-Host "WARNING: Debug file not found at $debugFile" -ForegroundColor Yellow
    Write-Host "         Run VHDL simulation first" -ForegroundColor Yellow
}

# Archive results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$archiveDir = "testbench_logs/real_data_tests/${Category}_${Index}_${timestamp}"
New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null

if (Test-Path $debugFile) {
    Copy-Item $debugFile "$archiveDir/vhdl_debug.txt"
}
if (Test-Path "model/intermediate_values.npz") {
    Copy-Item "model/intermediate_values.npz" "$archiveDir/python_reference.npz"
}
if (Test-Path "model/test_image_preview.png") {
    Copy-Item "model/test_image_preview.png" "$archiveDir/test_image.png"
}
if (Test-Path "model/test_image_reference.npz") {
    Copy-Item "model/test_image_reference.npz" "$archiveDir/test_image_reference.npz"
}

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "✓ Test complete! Results archived to:" -ForegroundColor Green
Write-Host "  $archiveDir" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green

# Summary
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  - Review comparison statistics above" -ForegroundColor White
Write-Host "  - Check for large errors (avg error should be < 0.2)" -ForegroundColor White
Write-Host "  - Inspect zero-filter warnings (should be < 50%)" -ForegroundColor White
Write-Host "  - Try different categories: .\test_real_data.ps1 -Category banana -Index 5" -ForegroundColor White
