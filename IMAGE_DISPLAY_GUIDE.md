# VGA Image Display Guide

## Overview
This guide explains how to display an image on your FPGA VGA output.

## Quick Start

### Step 1: Prepare Your Image
1. Place your image file in the project folder
2. Run the Python converter script:
   ```powershell
   python image_to_coe.py your_image.jpg 320 240
   ```
   This will resize your image to 320x240 and create a `.coe` file

### Step 2: Create Block RAM IP in Vivado
1. Open your Vivado project
2. In the Flow Navigator, click **IP Catalog**
3. Search for "Block Memory Generator"
4. Double-click to configure:
   - **Basic Tab:**
     - Memory Type: **Single Port ROM**
     - Port A Width: **12** bits
     - Port A Depth: **76800** (for 320x240) or your width × height
   - **Other Options Tab:**
     - Check "Load Init File"
     - Browse and select your `.coe` file
   - Click **OK** then **Generate**
5. Name it `image_ram` when prompted

### Step 3: Update Your VHDL Top File
You have two options:

#### Option A: Use the Prepared File
Replace your current `top.vhd` with the `top_image_display.vhd` template:
1. Update these constants in `top_image_display.vhd`:
   ```vhdl
   constant IMAGE_WIDTH : natural := 320;   -- Your image width
   constant IMAGE_HEIGHT : natural := 240;  -- Your image height
   ```
2. Set this as your top-level module in Vivado

#### Option B: Manually Modify Current Top File
See detailed instructions in section below.

### Step 4: Adjust VGA Resolution (Optional)
For 1920x1080 displays, you may want to use 640x480 VGA mode for better compatibility.
Change the clock wizard to output 25 MHz instead of 148.5 MHz:
1. Double-click `clk_wiz_0` IP in your project
2. Change output clock frequency to **25.000 MHz**
3. Regenerate the IP

Or use the provided TCL script:
```powershell
vivado -mode batch -source fix_vga_clock.tcl
```

### Step 5: Synthesize and Program
1. Run **Synthesis**
2. Run **Implementation**
3. Generate **Bitstream**
4. Program your FPGA

## Recommended Image Resolutions

| Resolution | Pixels   | RAM Usage | Best For |
|------------|----------|-----------|----------|
| 160×120    | 19,200   | ~75 KB    | Small icons/logos |
| 320×240    | 76,800   | ~300 KB   | **Recommended** - Good balance |
| 640×480    | 307,200  | ~1.2 MB   | Full screen (if RAM available) |

## Troubleshooting

### Image doesn't appear
- Check that `image_ram` component is correctly instantiated
- Verify the `.coe` file is loaded in Block RAM IP
- Confirm IMAGE_WIDTH and IMAGE_HEIGHT match your actual image size
- Check RAM address width (should be ceil(log2(width × height)))

### Synthesis errors about RAM
- Make sure Block RAM IP is generated before synthesis
- Check that the RAM component declaration matches the generated IP

### Colors look wrong
- The converter uses 12-bit RGB (4-4-4)
- Make sure your VGA signals are connected correctly

### Image appears but is distorted
- Verify IMAGE_WIDTH and IMAGE_HEIGHT constants
- Check that RAM depth = width × height
- Ensure COE file has correct number of pixels

## Technical Details

### Memory Format
- Each pixel is stored as 12-bit RGB: `RRRRGGGGBBBB`
- Pixels are stored row-by-row (row-major order)
- Address calculation: `address = y * IMAGE_WIDTH + x`

### Color Encoding
- 8-bit RGB input is converted to 4-bit per channel
- Red: bits [11:8]
- Green: bits [7:4]  
- Blue: bits [3:0]

### Timing
- The design uses look-ahead addressing to compensate for Block RAM latency
- One clock cycle delay is built into the addressing logic

## Files in This Project
- `image_to_coe.py` - Python script to convert images to COE format
- `top_image_display.vhd` - VHDL template for image display
- `top.vhd` - Your current VGA test pattern design
- `fix_vga_clock.tcl` - Script to reconfigure clock for 640×480 mode

## Python Requirements
Install PIL/Pillow if you don't have it:
```powershell
pip install Pillow
```
