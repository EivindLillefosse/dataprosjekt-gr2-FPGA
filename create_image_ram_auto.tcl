# TCL Script to create Block RAM IP for image storage
# Usage: vivado -mode batch -source create_image_ram.tcl -tclargs <width> <height> <coe_file_path>

if {$argc < 3} {
    puts "Usage: vivado -mode batch -source create_image_ram.tcl -tclargs <width> <height> <coe_file_path>"
    puts "Example: vivado -mode batch -source create_image_ram.tcl -tclargs 320 240 my_image.coe"
    exit 1
}

set image_width [lindex $argv 0]
set image_height [lindex $argv 1]
set coe_file [lindex $argv 2]
set ram_depth [expr $image_width * $image_height]
set addr_width [expr {int(ceil(log($ram_depth)/log(2)))}]

puts "Creating Block RAM IP for image display"
puts "Image size: ${image_width}x${image_height}"
puts "RAM depth: $ram_depth"
puts "Address width: $addr_width bits"
puts "COE file: $coe_file"

# Open project
set proj_file [glob -nocomplain *.xpr]
if {[llength $proj_file] == 0} {
    puts "ERROR: No Vivado project found in current directory"
    exit 1
}
open_project [lindex $proj_file 0]

# Create Block Memory Generator IP
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name image_ram

# Configure the IP
set_property -dict [list \
    CONFIG.Memory_Type {Single_Port_ROM} \
    CONFIG.Write_Width_A {12} \
    CONFIG.Read_Width_A {12} \
    CONFIG.Write_Depth_A $ram_depth \
    CONFIG.Read_Depth_A $ram_depth \
    CONFIG.Enable_A {Always_Enabled} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File [file normalize $coe_file] \
    CONFIG.Fill_Remaining_Memory_Locations {true} \
    CONFIG.Remaining_Memory_Locations {000} \
] [get_ips image_ram]

# Generate the IP
generate_target all [get_files image_ram.xci]
create_ip_run [get_files image_ram.xci]

puts "Block RAM IP 'image_ram' created successfully!"
puts "You can now synthesize the IP or use it in your design."

close_project
