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
    
    if {$memory_type == "weights"} {
        # For weights: shape is (kernel_h, kernel_w, in_channels, num_filters)
        # Memory organization: depth = kernel_h * kernel_w
        #                      width = num_filters * 8 bits
        set kernel_h [lindex $shape_list 0]
        set kernel_w [lindex $shape_list 1]
        set num_filters [lindex $shape_list 3]
        
        set depth [expr {$kernel_h * $kernel_w}]
        set width [expr {$num_filters * 8}]

        puts "Calculated depth: $depth, width: $width for weights"
        puts "  Total elements: $total_elements"
        
        dict set params depth $depth
        dict set params width $width
        dict set params description "Weights: ${kernel_h}x${kernel_w} kernel, ${num_filters} filters"
        
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
    if {[catch {
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
        
        puts "  ✓ IP $ip_name created successfully"
        return 1
    } result]} {
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
        set params [calculate_memory_params $metadata "weights"]
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
                create_bram_ip $ip_name $width $depth $coe_file $desc
                dict set created_ips $ip_name 1
            } else {
                puts "Skipping - IP $ip_name already exists"
            }
        }
        
    } elseif {[string match "*bias*" $filename]} {
        set params [calculate_memory_params $metadata "bias"]
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
                create_bram_ip $ip_name $width $depth $coe_file $desc
                dict set created_ips $ip_name 1
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

puts "\n=== Project Setup Complete ==="
puts "Project: $project_name"
puts "IPs added: [llength $all_ips]"
puts "Top module: $top_module"
