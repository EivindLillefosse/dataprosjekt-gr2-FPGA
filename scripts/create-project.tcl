# Create project with optional command-line parameters
# Usage: vivado -mode batch -source create-project.tcl -tclargs [part_number] [top_module] [project_name]
# Example: vivado -mode batch -source create-project.tcl -tclargs XC7A100TCSG324-1 my_top MyProject

# Set default values
set project_name "CNN"
set project_dir "./vivado_project"
set part_number "XC7A35TICSG324-1L"
set top_module "top"
set_param general.maxThreads 8

# Override with command-line arguments if provided
if {$argc > 0} {
    set part_arg [lindex $argv 0]
    if {$part_arg == "35"} {
        set part_number "XC7A35TICSG324-1L"
    } elseif {$part_arg == "100"} {
        set part_number "XC7A100TCSG324-1"
    } else {
        set part_number $part_arg
    }
    puts "Using part number: $part_number"
}
if {$argc > 1} {
    set top_module [lindex $argv 1]
    puts "Using top module: $top_module"
}
if {$argc > 2} {
    set project_name [lindex $argv 2]
    puts "Using project name: $project_name"
}

# Parameters with defaults (for backward compatibility)
if {![info exists part_number]} {
    set part_number "XC7A35TICSG324-1L"
}
if {![info exists top_module]} {
    set top_module "top"
}

# print out the final configuration
puts "Final Configuration:"
puts "Project Name: $project_name"
puts "Project Directory: $project_dir"
puts "Part Number: $part_number"
puts "Top Module: $top_module"

# Create the project
create_project $project_name $project_dir -part $part_number -force

# Start GUI
start_gui

# Recursive procedure to collect files matching a pattern
proc get_files_recursive {dir pattern} {
    set files [glob -nocomplain "$dir/$pattern"]
    foreach subdir [glob -nocomplain -type d "$dir/*"] {
        set files [concat $files [get_files_recursive $subdir $pattern]]
    }
    return $files
}

# Add VHDL source files (excluding *_tb.vhd)
set src_dir "./src"
if {[file isdirectory $src_dir]} {
    foreach file [get_files_recursive $src_dir "*.vhd"] {
        if {![string match "*_tb.vhd" $file]} {
            puts "Adding source: $file"
            add_files $file
        }
    }
    # Add testbench files to simulation fileset
    foreach file [get_files_recursive $src_dir "*_tb.vhd"] {
        puts "Adding testbench: $file"
        add_files -fileset sim_1 $file
    }
} else {
    puts "Warning: Source directory '$src_dir' does not exist."
}

# Add constraint files from constraints directory
set constraints_dir "./constraints"
if {[file isdirectory $constraints_dir]} {
    foreach xdc_file [glob -nocomplain "$constraints_dir/*.xdc"] {
        puts "Adding constraint: $xdc_file"
        add_files -fileset constrs_1 $xdc_file
    }
} else {
    puts "Warning: Constraints directory '$constraints_dir' does not exist."
}

# Add IP cores from memory directory
puts "\n=== Adding IP Cores ==="
set memory_dir "./src/memory"
if {[file isdirectory $memory_dir]} {
    # Find all .xci files in the memory directory
    set ip_files [glob -nocomplain "$memory_dir/*.xci"]
    
    if {[llength $ip_files] > 0} {
        puts "Found [llength $ip_files] IP core(s) in $memory_dir"
        
        foreach ip_file $ip_files {
            set ip_name [file tail [file rootname $ip_file]]
            puts "Adding IP: $ip_name ($ip_file)"
            
            if {[catch {add_files $ip_file} result]} {
                puts "Warning: Failed to add IP $ip_name: $result"
            } else {
                puts "Successfully added IP: $ip_name"
            }
        }
    } else {
        puts "No IP cores (.xci files) found in $memory_dir"
    }
    
    # Also check for any subdirectories that might contain IP cores
    foreach subdir [glob -nocomplain -type d "$memory_dir/*"] {
        set sub_ip_files [glob -nocomplain "$subdir/*.xci"]
        if {[llength $sub_ip_files] > 0} {
            puts "Found [llength $sub_ip_files] IP core(s) in [file tail $subdir]"
            
            foreach ip_file $sub_ip_files {
                set ip_name [file tail [file rootname $ip_file]]
                puts "Adding IP: $ip_name ($ip_file)"
                
                if {[catch {add_files $ip_file} result]} {
                    puts "Warning: Failed to add IP $ip_name: $result"
                } else {
                    puts "Successfully added IP: $ip_name"
                }
            }
        }
    }
} else {
    puts "Warning: Memory directory '$memory_dir' does not exist."
}

# Fix COE file paths before IP generation
puts "\n=== Fixing COE File Paths ==="
set all_ips [get_ips]
if {[llength $all_ips] > 0} {
    foreach ip $all_ips {
        # Get current COE file path
        if {[catch {set current_coe [get_property CONFIG.Coe_File [get_ips $ip]]} result]} {
            puts "IP $ip does not use COE files"
            continue
        }
        
        if {$current_coe != ""} {
            puts "Updating COE path for IP: $ip"
            puts "Current path: $current_coe"
            
            # Convert to absolute path
            if {[string match "*weights*" $ip]} {
                set abs_coe_path [file normalize "./model/fpga_weights_and_bias/layer_0_conv2d_weights.coe"]
            } elseif {[string match "*bias*" $ip]} {
                set abs_coe_path [file normalize "./model/fpga_weights_and_bias/layer_0_conv2d_biases.coe"]
            } else {
                puts "Warning: Unknown IP type for $ip, skipping COE update"
                continue
            }
            
            if {[file exists $abs_coe_path]} {
                puts "Setting absolute COE path: $abs_coe_path"
                set_property CONFIG.Coe_File $abs_coe_path [get_ips $ip]
            } else {
                puts "Warning: COE file not found: $abs_coe_path"
            }
        }
    }
}

# Generate IP output products
puts "\n=== Generating IP Output Products ==="
if {[llength $all_ips] > 0} {
    puts "Found IPs: $all_ips"
    foreach ip $all_ips {
        puts "Generating output products for: $ip"
        if {[catch {generate_target all [get_files [get_property IP_FILE [get_ips $ip]]]} result]} {
            puts "Warning: Failed to generate IP $ip: $result"
        } else {
            puts "Successfully generated IP: $ip"
        }
    }
    
    # Update compile order to include generated IP files
    update_compile_order -fileset sources_1
    puts "IP generation complete."
} else {
    puts "No IP cores found in project."
}

# Verify COE file paths (optional check)
puts "\n=== Verifying COE Files ==="
set coe_weights "./model/fpga_weights_and_bias/layer_0_conv2d_weights.coe"
set coe_biases "./model/fpga_weights_and_bias/layer_0_conv2d_biases.coe"

if {[file exists $coe_weights]} {
    puts "✓ Weight COE file found: $coe_weights"
} else {
    puts "✗ Weight COE file missing: $coe_weights"
}

if {[file exists $coe_biases]} {
    puts "✓ Bias COE file found: $coe_biases"
} else {
    puts "✗ Bias COE file missing: $coe_biases"
}

# Set top module
set_property top $top_module [current_fileset]

puts "\n=== Project Setup Complete ==="
puts "Project: $project_name"
puts "IPs added: [llength $all_ips]"
puts "Top module: $top_module"
