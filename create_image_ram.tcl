# TCL Script to create Block RAM IP for image storage
# Run this in Vivado TCL console after generating your .coe file

# Configuration - EDIT THESE VALUES
set IMAGE_WIDTH 640
set IMAGE_HEIGHT 480
set COE_FILE_PATH "your_image_640x480.coe"

# Calculate memory depth
set MEM_DEPTH [expr $IMAGE_WIDTH * $IMAGE_HEIGHT]

puts "Creating Block RAM for ${IMAGE_WIDTH}x${IMAGE_HEIGHT} image..."
puts "Memory depth: $MEM_DEPTH"

# Open project
open_project VGA_prosjekt.xpr

# Create Block Memory Generator IP
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name image_ram

# Configure the Block RAM
set_property -dict [list \
    CONFIG.Memory_Type {Single_Port_ROM} \
    CONFIG.Write_Width_A {12} \
    CONFIG.Write_Depth_A $MEM_DEPTH \
    CONFIG.Read_Width_A {12} \
    CONFIG.Enable_A {Always_Enabled} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File [file normalize $COE_FILE_PATH] \
    CONFIG.Use_RSTA_Pin {false} \
] [get_ips image_ram]

# Generate the IP
generate_target all [get_ips image_ram]
create_ip_run [get_ips image_ram]

puts "Block RAM IP created successfully!"
puts ""
puts "Next steps:"
puts "1. Add top_image_display.vhd to your project sources"
puts "2. Update the clock wizard for 25.175 MHz (640x480) if needed"
puts "3. Run synthesis and implementation"

# Save project
save_project
