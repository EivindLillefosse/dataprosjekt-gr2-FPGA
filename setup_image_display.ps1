# PowerShell Script to Setup Image Display
# This script automates the process of converting an image and creating the RAM IP

param(
    [Parameter(Mandatory=$true)]
    [string]$ImagePath,
    
    [Parameter(Mandatory=$false)]
    [int]$Width = 320,
    
    [Parameter(Mandatory=$false)]
    [int]$Height = 240
)

Write-Host "=== VGA Image Display Setup ===" -ForegroundColor Cyan
Write-Host ""

# Check if image file exists
if (-not (Test-Path $ImagePath)) {
    Write-Host "ERROR: Image file not found: $ImagePath" -ForegroundColor Red
    exit 1
}

# Check if Python is available
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Found Python: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Python not found. Please install Python and try again." -ForegroundColor Red
    exit 1
}

# Check if Pillow is installed
Write-Host "Checking for Pillow library..." -ForegroundColor Yellow
$pillowCheck = python -c "import PIL; print('OK')" 2>&1
if ($pillowCheck -ne "OK") {
    Write-Host "Pillow not found. Installing..." -ForegroundColor Yellow
    pip install Pillow
}

# Step 1: Convert image to COE
Write-Host ""
Write-Host "Step 1: Converting image to COE format..." -ForegroundColor Cyan
$imageName = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath)
$coeFile = "${imageName}_${Width}x${Height}.coe"

python image_to_coe.py $ImagePath $Width $Height

if (-not (Test-Path $coeFile)) {
    Write-Host "ERROR: COE file was not created" -ForegroundColor Red
    exit 1
}

Write-Host "COE file created: $coeFile" -ForegroundColor Green

# Step 2: Show instructions for Vivado
Write-Host ""
Write-Host "Step 2: Create Block RAM IP in Vivado" -ForegroundColor Cyan
Write-Host ""
Write-Host "You have two options:" -ForegroundColor Yellow
Write-Host ""
Write-Host "OPTION A - Manual (GUI):" -ForegroundColor White
Write-Host "  1. Open your Vivado project"
Write-Host "  2. Click IP Catalog -> Block Memory Generator"
Write-Host "  3. Configure:"
Write-Host "     - Memory Type: Single Port ROM"
Write-Host "     - Port Width: 12 bits"
Write-Host "     - Port Depth: $($Width * $Height)"
Write-Host "     - Load Init File: $coeFile"
Write-Host "  4. Name it 'image_ram' and generate"
Write-Host ""
Write-Host "OPTION B - Automatic (TCL Script):" -ForegroundColor White
Write-Host "  Run this command:"
Write-Host "  vivado -mode batch -source create_image_ram_auto.tcl -tclargs $Width $Height $coeFile" -ForegroundColor Cyan
Write-Host ""

# Step 3: Update VHDL constants
Write-Host "Step 3: Update your VHDL file" -ForegroundColor Cyan
Write-Host ""
Write-Host "Update these constants in top_image_display.vhd:" -ForegroundColor White
Write-Host "  constant IMAGE_WIDTH : natural := $Width;"
Write-Host "  constant IMAGE_HEIGHT : natural := $Height;"
Write-Host ""

# Calculate required address width
$ramDepth = $Width * $Height
$addrWidth = [Math]::Ceiling([Math]::Log($ramDepth, 2))

Write-Host "Also verify the address width in the component declaration:" -ForegroundColor White
Write-Host "  addra : in std_logic_vector($($addrWidth - 1) downto 0);"
Write-Host ""

Write-Host "=== Setup Summary ===" -ForegroundColor Cyan
Write-Host "Image: $ImagePath"
Write-Host "Resolution: ${Width}x${Height}"
Write-Host "Total pixels: $ramDepth"
Write-Host "Address width: $addrWidth bits"
Write-Host "COE file: $coeFile"
Write-Host ""
Write-Host "Next: Follow the Vivado steps above, then synthesize and program your FPGA!" -ForegroundColor Green
