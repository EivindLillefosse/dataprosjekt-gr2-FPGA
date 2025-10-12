# Create project with optional command-line parameters
# Usage: 
#   With GUI: vivado -source create-project.tcl -tclargs [part_number] [top_module] [project_name]
#   Batch mode: vivado -mode batch -source create-project.tcl -tclargs [part_number] [top_module] [project_name]
# Example: vivado -source create-project.tcl -tclargs 100 top my_proj

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

# Start GUI (will only work if Vivado was launched in GUI mode, not batch mode)
# To run with GUI: vivado -source scripts/create-project.tcl -tclargs 35
# To run without GUI: vivado -mode batch -source scripts/create-project.tcl -tclargs 35
if {[catch {start_gui} err]} {
    puts "Note: Running in batch mode (GUI not available)"
} else {
    puts "GUI started successfully"
}

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

# Ensure Vivado treats VHDL sources as VHDL-2019
puts "\nSetting VHDL standard to 2019 for all VHDL files..."
foreach vfile [get_files_recursive $src_dir "*.vhd"] {
    if {[catch {set_property FILE_TYPE {VHDL 2019} [get_files $vfile]} err]} {
        puts "Warning: failed to set FILE_TYPE for $vfile : $err"
    } else {
        puts "  Set VHDL 2019 for: $vfile"
    }
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

# ============================================================================
# Procedure to parse COE file metadata
# ============================================================================
proc parse_coe_metadata {coe_file} {
    set metadata [dict create]
    
    if {![file exists $coe_file]} {
        puts "Warning: COE file not found: $coe_file"
        return $metadata
    }
    
    set fp [open $coe_file r]
    set content [read $fp]
    close $fp
    
    # Parse metadata from comments
    foreach line [split $content "\n"] {
        set line [string trim $line]
        
        # Extract shape information
        if {[regexp {Original shape:\s*\(([^)]+)\)} $line -> shape_str]} {
            dict set metadata shape $shape_str
            # Parse shape tuple (e.g., "3, 3, 1, 8")
            set shape_values [split $shape_str ","]
            set cleaned_values {}
            foreach val $shape_values {
                set trimmed [string trim $val]
                # Only add non-empty values (filter out trailing comma)
                if {$trimmed != ""} {
                    lappend cleaned_values $trimmed
                }
            }
            dict set metadata shape_list $cleaned_values
        }
        
        # Alternative shape format (for biases)
        if {[regexp {Shape:\s*\(([^)]+)\)} $line -> shape_str]} {
            dict set metadata shape $shape_str
            set shape_values [split $shape_str ","]
            set cleaned_values {}
            foreach val $shape_values {
                set trimmed [string trim $val]
                # Only add non-empty values (filter out trailing comma)
                if {$trimmed != ""} {
                    lappend cleaned_values $trimmed
                }
            }
            dict set metadata shape_list $cleaned_values
        }
        
        # Extract total elements
        if {[regexp {Total elements:\s*(\d+)} $line -> total]} {
            dict set metadata total_elements $total
        }
        
        # Extract layer type
        if {[regexp {Layer (\d+):\s*(\w+)} $line -> layer_num layer_type]} {
            dict set metadata layer_number $layer_num
            dict set metadata layer_type $layer_type
        }
    }
    
    return $metadata
}

# ============================================================================
# Procedure to calculate memory parameters from COE metadata
# ============================================================================
proc calculate_memory_params {metadata memory_type} {
    set params [dict create]
    
    if {![dict exists $metadata shape_list]} {
        puts "Warning: No shape information found in COE metadata"
        return $params
    }
    
    set shape_list [dict get $metadata shape_list]
    set total_elements [dict get $metadata total_elements]
    set layer_type [dict get $metadata layer_type]
    set num_dims [llength $shape_list]
    
    if {$memory_type == "weights"} {
        if {$layer_type == "dense"} {
            # Dense layer weights: shape is (input_dim, output_dim)
            # Memory organization: depth = input_dim
            #                      width = output_dim * 8 bits
            set input_dim [lindex $shape_list 0]
            set output_dim [lindex $shape_list 1]
            
            set depth $input_dim
            set width [expr {$output_dim * 8}]
            
            puts "Calculated depth: $depth, width: $width for dense weights"
            puts "  Total elements: $total_elements"
            
            dict set params depth $depth
            dict set params width $width
            dict set params description "Dense: ${input_dim}x${output_dim} weights"
            
        } else {
            # Conv layer weights: shape is (kernel_h, kernel_w, in_channels, num_filters)
            # Memory organization: depth = kernel_h * kernel_w
            #                      width = num_filters * 8 bits
            set kernel_h [lindex $shape_list 0]
            set kernel_w [lindex $shape_list 1]
            set num_filters [lindex $shape_list 3]
            
            set depth [expr {$kernel_h * $kernel_w}]
            set width [expr {$num_filters * 8}]

            puts "Calculated depth: $depth, width: $width for conv weights"
            puts "  Total elements: $total_elements"
            
            dict set params depth $depth
            dict set params width $width
            dict set params description "Weights: ${kernel_h}x${kernel_w} kernel, ${num_filters} filters"
        }
        
    } elseif {$memory_type == "bias"} {
        # For biases: shape is (num_filters,)
        # Memory organization: depth = num_filters (one address per bias)
        #                      width = 8 bits (unpacked, individual values)
        set num_filters [lindex $shape_list 0]
        
        set depth $num_filters
        set width 8
        
        dict set params depth $depth
        dict set params width $width
        dict set params description "Biases: ${num_filters} filters (unpacked)"
    }
    
    return $params
}

# ============================================================================
# Procedure to create Block Memory Generator IP
# ============================================================================
proc create_bram_ip {ip_name width depth coe_file {description "Block RAM"}} {
    puts "\nCreating IP: $ip_name"
    puts "  Description: $description"
    puts "  Width: $width bits"
    puts "  Depth: $depth words"
    puts "  COE file: $coe_file"
    
    # Calculate address width
    set addr_width [expr {int(ceil(log($depth)/log(2)))}]
    if {$addr_width < 1} {set addr_width 1}
    puts "  Address width: $addr_width bits"
    
    # Create the IP
    set error_code [catch {
        create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 \
                  -module_name $ip_name -dir ./ip_repo
        
        # Configure the IP
        set_property -dict [list \
            CONFIG.Memory_Type {Single_Port_ROM} \
            CONFIG.Write_Width_A $width \
            CONFIG.Write_Depth_A $depth \
            CONFIG.Read_Width_A $width \
            CONFIG.Enable_A {Use_ENA_Pin} \
            CONFIG.Register_PortA_Output_of_Memory_Primitives {true} \
            CONFIG.Register_PortA_Output_of_Memory_Core {false} \
            CONFIG.Use_REGCEA_Pin {false} \
            CONFIG.Load_Init_File {true} \
            CONFIG.Coe_File $coe_file \
            CONFIG.Fill_Remaining_Memory_Locations {false} \
            CONFIG.Use_RSTA_Pin {false} \
            CONFIG.Port_A_Write_Rate {0} \
            CONFIG.Port_A_Enable_Rate {100} \
            CONFIG.Algorithm {Minimum_Area} \
        ] [get_ips $ip_name]
    } result]
    
    if {$error_code == 0} {
        puts "  ✓ IP $ip_name created successfully"
        return 1
    } else {
        puts "  ✗ Failed to create IP $ip_name: $result"
        return 0
    }
}

# ============================================================================
# Search for and process COE files
# ============================================================================
puts "\n=== Searching for COE Files ==="
set memory_dir "./src/memory"
set coe_search_dirs [list "./model/fpga_weights_and_bias" "./model" "."]

set found_coe_files [list]

foreach search_dir $coe_search_dirs {
    if {[file isdirectory $search_dir]} {
        set coe_files [glob -nocomplain "$search_dir/*.coe"]
        foreach coe_file $coe_files {
            lappend found_coe_files [file normalize $coe_file]
        }
    }
}

# Remove duplicates
set found_coe_files [lsort -unique $found_coe_files]

if {[llength $found_coe_files] == 0} {
    puts "WARNING: No COE files found in search directories"
    puts "Searched in: $coe_search_dirs"
} else {
    puts "Found [llength $found_coe_files] COE file(s):"
    foreach coe $found_coe_files {
        puts "  - $coe"
    }
}

# ============================================================================
# Parse COE files and create IPs
# ============================================================================
puts "\n=== Creating/Adding IP Cores ==="

# Track which IPs have been created by name (to avoid duplicates)
set created_ips [dict create]

# Check for existing IPs first
if {[file isdirectory $memory_dir]} {
    set ip_files [glob -nocomplain "$memory_dir/*/*.xci"]
    foreach ip_file $ip_files {
        set ip_basename [file rootname [file tail $ip_file]]
        puts "Found existing IP: $ip_file"
        add_files $ip_file
        dict set created_ips $ip_basename 1
    }
}

# Process each COE file
foreach coe_file $found_coe_files {
    set filename [file tail $coe_file]
    
    puts "\n--- Processing: $filename ---"
    
    # Parse metadata
    set metadata [parse_coe_metadata $coe_file]
    
    if {[dict exists $metadata layer_type]} {
        puts "Layer [dict get $metadata layer_number]: [dict get $metadata layer_type]"
    }
    if {[dict exists $metadata shape]} {
        puts "Shape: [dict get $metadata shape]"
    }
    if {[dict exists $metadata total_elements]} {
        puts "Total elements: [dict get $metadata total_elements]"
    }
    
    # Determine memory type and create IP
    if {[string match "*weight*" $filename]} {
        if {[catch {set params [calculate_memory_params $metadata "weights"]} err]} {
            puts "  ✗ Error calculating parameters: $err"
            puts "  Skipping this file"
            continue
        }
        if {[dict size $params] > 0} {
            set width [dict get $params width]
            set depth [dict get $params depth]
            set desc [dict get $params description]
            
            # Extract layer name from filename (e.g., "layer_0_conv2d_weights.coe" -> "conv2d")
            set layer_num [dict get $metadata layer_number]
            set layer_type [dict get $metadata layer_type]
            set ip_name "layer${layer_num}_${layer_type}_weights"
            
            # Check if this specific IP already exists
            if {![dict exists $created_ips $ip_name]} {
                set success [create_bram_ip $ip_name $width $depth $coe_file $desc]
                if {$success} {
                    dict set created_ips $ip_name 1
                } else {
                    puts "  Note: IP creation failed, continuing with next file"
                }
            } else {
                puts "Skipping - IP $ip_name already exists"
            }
        }
        
    } elseif {[string match "*bias*" $filename]} {
        if {[catch {set params [calculate_memory_params $metadata "bias"]} err]} {
            puts "  ✗ Error calculating parameters: $err"
            puts "  Skipping this file"
            continue
        }
        if {[dict size $params] > 0} {
            set width [dict get $params width]
            set depth [dict get $params depth]
            set desc [dict get $params description]
            
            # Extract layer name from filename (e.g., "layer_0_conv2d_biases.coe" -> "conv2d")
            set layer_num [dict get $metadata layer_number]
            set layer_type [dict get $metadata layer_type]
            set ip_name "layer${layer_num}_${layer_type}_biases"
            
            # Check if this specific IP already exists
            if {![dict exists $created_ips $ip_name]} {
                set success [create_bram_ip $ip_name $width $depth $coe_file $desc]
                if {$success} {
                    dict set created_ips $ip_name 1
                } else {
                    puts "  Note: IP creation failed, continuing with next file"
                }
            } else {
                puts "Skipping - IP $ip_name already exists"
            }
        }
    }
}

# Generate IP output products
puts "\n=== Generating IP Output Products ==="
set all_ips [get_ips]
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

# ============================================================================
# Add UVVM support
# ============================================================================
puts "\n=== Adding UVVM Support ==="
set uvvm_root "./UVVM"
set uvvm_compile_script "$uvvm_root/script/compile_all.do"

if {[file exists $uvvm_compile_script] && [file isdirectory $uvvm_root]} {
    puts "Found UVVM installation: $uvvm_root"
    
    # Get absolute paths for UVVM
    set uvvm_abs_path [file normalize $uvvm_root]
    set project_abs_path [file normalize $project_dir]
    
    puts "  UVVM path: $uvvm_abs_path"
    puts "  Project path: $project_abs_path"
    
    # Create UVVM compilation script for Vivado
    set uvvm_compile_tcl "$project_dir/compile_uvvm.tcl"
    set fp [open $uvvm_compile_tcl w]
    puts $fp "# UVVM Compilation Script for Vivado"
    puts $fp "# Generated automatically by create-project.tcl"
    puts $fp "#"
    puts $fp "# Note: UVVM requires VHDL-2008 or newer"
    puts $fp ""
    puts $fp "puts \"=== Compiling UVVM Libraries ===\""
    puts $fp ""
    puts $fp "# Set UVVM library compilation order"
    puts $fp "set uvvm_libs \[list \\"
    puts $fp "    uvvm_util \\"
    puts $fp "    uvvm_vvc_framework \\"
    puts $fp "    bitvis_vip_scoreboard \\"
    puts $fp "\]"
    puts $fp ""
    puts $fp "# Add other VIPs as needed, e.g.:"
    puts $fp "# lappend uvvm_libs bitvis_vip_sbi"
    puts $fp "# lappend uvvm_libs bitvis_vip_uart"
    puts $fp "# lappend uvvm_libs bitvis_vip_avalon_mm"
    puts $fp ""
    puts $fp "set uvvm_path \"$uvvm_abs_path\""
    puts $fp ""
    puts $fp "foreach lib \$uvvm_libs \{"
    puts $fp "    set lib_path \"\$uvvm_path/\$lib\""
    puts $fp "    if \{\[file isdirectory \$lib_path\]\} \{"
    puts $fp "        puts \"Compiling \$lib...\""
    puts $fp "        "
    puts $fp "        # Create library if it doesn't exist"
    puts $fp "        if \{\[catch \{create_fileset -simset \$lib\}\]\} \{"
    puts $fp "            puts \"  Library \$lib already exists\""
    puts $fp "        \}"
    puts $fp "        "
    puts $fp "        # Find and add all VHDL source files"
    puts $fp "        set src_path \"\$lib_path/src\""
    puts $fp "        if \{\[file isdirectory \$src_path\]\} \{"
    puts $fp "            set vhd_files \[glob -nocomplain \$src_path/*.vhd\]"
    puts $fp "            foreach vhd_file \$vhd_files \{"
    puts $fp "                puts \"  Adding: \$vhd_file\""
    puts $fp "                add_files -fileset sim_1 \$vhd_file"
    puts $fp "                # Ensure VHDL-2008 is used"
    puts $fp "                set_property FILE_TYPE \{VHDL 2008\} \[get_files \$vhd_file\]"
    puts $fp "                set_property LIBRARY \$lib \[get_files \$vhd_file\]"
    puts $fp "            \}"
    puts $fp "        \} else \{"
    puts $fp "            puts \"  Warning: Source directory not found: \$src_path\""
    puts $fp "        \}"
    puts $fp "    \} else \{"
    puts $fp "        puts \"  Warning: Library directory not found: \$lib_path\""
    puts $fp "    \}"
    puts $fp "\}"
    puts $fp ""
    puts $fp "puts \"=== UVVM Compilation Complete ===\""
    puts $fp "update_compile_order -fileset sim_1"
    close $fp
    puts "  ✓ Created UVVM compilation script: $uvvm_compile_tcl"
    
    # Create a simulation helper script
    set sim_script "$project_dir/simulate.tcl"
    set fp [open $sim_script w]
    puts $fp "# Simulation Helper Script"
    puts $fp "# Usage: source simulate.tcl"
    puts $fp ""
    puts $fp "# Compile UVVM libraries (if not already compiled)"
    puts $fp "# source compile_uvvm.tcl"
    puts $fp ""
    puts $fp "# Set simulation top"
    puts $fp "# set_property top <testbench_name> \[get_filesets sim_1\]"
    puts $fp ""
    puts $fp "# Launch simulation"
    puts $fp "# launch_simulation"
    puts $fp ""
    puts $fp "# Run simulation"
    puts $fp "# run all"
    close $fp
    puts "  ✓ Created simulation helper script: $sim_script"
    
    # Optionally compile UVVM libraries now (commented out by default)
    puts ""
    puts "To compile UVVM libraries, run from Vivado TCL console:"
    puts "  source $project_dir/compile_uvvm.tcl"
    puts ""
    puts "Or from command line:"
    puts "  vivado -mode batch -source $project_dir/compile_uvvm.tcl"
    
} else {
    puts "Warning: UVVM not found at: $uvvm_root"
    puts "  Expected compile script: $uvvm_compile_script"
    puts "  Skipping UVVM integration."
    puts ""
    puts "To install UVVM:"
    puts "  git clone https://github.com/UVVM/UVVM.git"
    puts "  or download from: https://github.com/UVVM/UVVM"
}

puts "\n=== Project Setup Complete ==="
puts "Project: $project_name"
puts "IPs added: [llength $all_ips]"
puts "Top module: $top_module"