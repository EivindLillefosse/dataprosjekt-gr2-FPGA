# UVVM Compilation Script for Vivado
# Generated automatically by create-project.tcl
#
# Note: UVVM requires VHDL-2008 or newer

puts "=== Compiling UVVM Libraries ==="

# Set UVVM library compilation order
set uvvm_libs [list \
    uvvm_util \
    uvvm_vvc_framework \
    bitvis_vip_scoreboard \
]

# Add other VIPs as needed, e.g.:
# lappend uvvm_libs bitvis_vip_sbi
# lappend uvvm_libs bitvis_vip_uart
# lappend uvvm_libs bitvis_vip_avalon_mm

set uvvm_path "C:/Users/eivin/Documents/Skule/FPGA/dataprosjekt-gr2-FPGA/UVVM"

foreach lib $uvvm_libs {
    set lib_path "$uvvm_path/$lib"
    if {[file isdirectory $lib_path]} {
        puts "Compiling $lib..."
        
        # Create library if it doesn't exist
        if {[catch {create_fileset -simset $lib}]} {
            puts "  Library $lib already exists"
        }
        
        # Find and add all VHDL source files
        set src_path "$lib_path/src"
        if {[file isdirectory $src_path]} {
            set vhd_files [glob -nocomplain $src_path/*.vhd]
            foreach vhd_file $vhd_files {
                puts "  Adding: $vhd_file"
                add_files -fileset sim_1 $vhd_file
                # Ensure VHDL-2008 is used
                set_property FILE_TYPE {VHDL 2008} [get_files $vhd_file]
                set_property LIBRARY $lib [get_files $vhd_file]
            }
        } else {
            puts "  Warning: Source directory not found: $src_path"
        }
    } else {
        puts "  Warning: Library directory not found: $lib_path"
    }
}

puts "=== UVVM Compilation Complete ==="
update_compile_order -fileset sim_1
