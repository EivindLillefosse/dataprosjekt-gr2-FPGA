"""
Image to COE File Converter for Vivado Block RAM
Converts an image to a .coe file with 12-bit RGB color (4 bits per channel)
"""

from PIL import Image
import sys
import os

def image_to_coe(image_path, output_path=None, target_width=None, target_height=None):
    """
    Convert an image to a COE file for Vivado Block RAM
    
    Args:
        image_path: Path to input image
        output_path: Path to output .coe file (optional)
        target_width: Target width (optional, will resize if specified)
        target_height: Target height (optional, will resize if specified)
    """
    
    # Load image
    try:
        img = Image.open(image_path)
        print(f"Loaded image: {image_path}")
        print(f"Original size: {img.size[0]}x{img.size[1]}")
    except Exception as e:
        print(f"Error loading image: {e}")
        return
    
    # Convert to RGB if necessary
    if img.mode != 'RGB':
        img = img.convert('RGB')
        print(f"Converted image to RGB mode")
    
    # Resize if target dimensions specified
    if target_width and target_height:
        img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
        print(f"Resized to: {target_width}x{target_height}")
    
    width, height = img.size
    
    # Generate output filename if not specified
    if output_path is None:
        base_name = os.path.splitext(image_path)[0]
        output_path = f"{base_name}_{width}x{height}.coe"
    
    # Open output file
    with open(output_path, 'w') as f:
        # Write COE header
        f.write("; COE file for Vivado Block RAM\n")
        f.write(f"; Image: {os.path.basename(image_path)}\n")
        f.write(f"; Resolution: {width}x{height}\n")
        f.write(f"; Total pixels: {width * height}\n")
        f.write("; Format: 12-bit RGB (4 bits per channel)\n")
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        
        # Convert each pixel to 12-bit RGB
        pixel_count = 0
        for y in range(height):
            for x in range(width):
                r, g, b = img.getpixel((x, y))
                
                # Convert 8-bit RGB to 4-bit RGB
                r4 = r >> 4  # Take upper 4 bits
                g4 = g >> 4
                b4 = b >> 4
                
                # Combine into 12-bit value: RRRRGGGGBBBB
                pixel_12bit = (r4 << 8) | (g4 << 4) | b4
                
                # Write as 3-digit hex
                if pixel_count < (width * height - 1):
                    f.write(f"{pixel_12bit:03X},\n")
                else:
                    f.write(f"{pixel_12bit:03X};\n")  # Last pixel ends with semicolon
                
                pixel_count += 1
            
            # Progress indicator
            if (y + 1) % 50 == 0:
                print(f"Processing: {y + 1}/{height} rows ({(y+1)/height*100:.1f}%)")
    
    print(f"\nCOE file created: {output_path}")
    print(f"Total pixels: {pixel_count}")
    print(f"\nNext steps:")
    print(f"1. Update IMAGE_WIDTH and IMAGE_HEIGHT constants in your VHDL to {width} and {height}")
    print(f"2. Create Block RAM IP in Vivado with:")
    print(f"   - Memory Type: Single Port ROM")
    print(f"   - Port A Width: 12 bits")
    print(f"   - Port A Depth: {width * height}")
    print(f"   - Load this COE file as initialization file")
    
    return output_path

def main():
    if len(sys.argv) < 2:
        print("Usage: python image_to_coe.py <image_path> [width] [height]")
        print("\nExample:")
        print("  python image_to_coe.py my_image.jpg")
        print("  python image_to_coe.py my_image.jpg 320 240")
        print("\nSupported formats: PNG, JPG, BMP, GIF, etc.")
        print("\nRecommended resolutions:")
        print("  - 320x240 (76,800 pixels, ~300KB RAM)")
        print("  - 640x480 (307,200 pixels, ~1.2MB RAM)")
        print("  - 160x120 (19,200 pixels, ~75KB RAM)")
        return
    
    image_path = sys.argv[1]
    
    target_width = None
    target_height = None
    
    if len(sys.argv) >= 4:
        try:
            target_width = int(sys.argv[2])
            target_height = int(sys.argv[3])
        except ValueError:
            print("Error: Width and height must be integers")
            return
    
    image_to_coe(image_path, target_width=target_width, target_height=target_height)

if __name__ == "__main__":
    main()
