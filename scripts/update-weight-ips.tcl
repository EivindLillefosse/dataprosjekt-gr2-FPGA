# Update IP cores with new COE files
# Run from workspace root: vivado -mode batch -source scripts/update-weight-ips.tcl

puts "=========================================="
puts "Updating Weight/Bias IP Cores with New COE Files"
puts "=========================================="

# Open the project
set proj_file "vivado_project/CNN.xpr"
if {![file exists $proj_file]} {
    puts "ERROR: Project file not found: $proj_file"
    exit 1
}

puts "Opening project: $proj_file"
open_project $proj_file

# Define IP-to-COE mappings
set ip_coe_map [dict create \
    "layer0_conv2d_weights" "model/fpga_weights_and_bias/layer_0_conv2d_weights.coe" \
    "layer0_conv2d_biases" "model/fpga_weights_and_bias/layer_0_conv2d_biases.coe" \
    "layer2_conv2d_1_weights" "model/fpga_weights_and_bias/layer_2_conv2d_1_weights.coe" \
    "layer2_conv2d_1_biases" "model/fpga_weights_and_bias/layer_2_conv2d_1_biases.coe" \
    "layer5_dense_weights" "model/fpga_weights_and_bias/layer_5_dense_weights.coe" \
    "layer5_dense_biases" "model/fpga_weights_and_bias/layer_5_dense_biases.coe" \
    "layer6_dense_1_biases" "model/fpga_weights_and_bias/layer_6_dense_1_biases.coe" \
]

set updated_count 0
dict for {ip_name coe_file} $ip_coe_map {
    puts "\n--- Updating IP: $ip_name ---"
   
    # Check if COE file exists
    if {![file exists $coe_file]} {
        puts "WARNING: COE file not found: $coe_file"
        continue
    }
    
    # Check if IP exists
    set ip_list [get_ips $ip_name]
    if {[llength $ip_list] == 0} {
        puts "WARNING: IP not found in project: $ip_name"
        continue
    }
    
    set ip_obj [lindex $ip_list 0]
    set coe_abs [file normalize $coe_file]
    
    puts "Updating COE file to: $coe_abs"
    
    # Update the COE file property
    if {[catch {
        set_property -dict [list CONFIG.Coe_File $coe_abs] $ip_obj
        puts "✓ COE file path updated"
        
        # Regenerate output products
        puts "Regenerating IP outputs..."
        generate_target all [get_files [get_property IP_FILE $ip_obj]]
        puts "✓ IP outputs regenerated"
        
        incr updated_count
    } err]} {
        puts "ERROR updating $ip_name: $err"
    }
}

puts "\n=========================================="
puts "Update Summary"
puts "=========================================="
puts "Updated $updated_count IP core(s)"

if {$updated_count > 0} {
    puts "\n✓ IP cores updated successfully!"
    puts "\nNext steps:"
    puts "  1. Close this script"
    puts "  2. Run testbench: vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs conv_layer_modular_tb"
    puts "  3. Verify with: python model/debug_comparison.py ..."
} else {
    puts "\n✗ No IP cores were updated. Check warnings above."
}

close_project
puts "\nProject closed."
