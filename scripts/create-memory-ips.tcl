# ============================================================================
# Create Memory IP Cores for CNN Accelerator
# ============================================================================
# This script creates Block Memory Generator IP cores for weights and biases
# Usage: vivado -mode batch -source create-memory-ips.tcl
# Or source this from within Vivado: source create-memory-ips.tcl
# ============================================================================

# ============================================================================
# Create Memory IP Cores for CNN Accelerator
# ============================================================================
# This script automatically discovers COE files and creates Block Memory 
# Generator IP cores with parameters extracted from the COE file metadata
# Usage: vivado -mode batch -source create-memory-ips.tcl
# Or source this from within Vivado: source create-memory-ips.tcl
# ============================================================================

puts "\n=========================================="
puts "Creating Memory IP Cores for CNN"
puts "=========================================="

# IP output directory
set ip_output_dir "../src/memory"
file mkdir $ip_output_dir

# ============================================================================
# Procedure to parse COE file metadata
# ============================================================================
proc parse_coe_metadata {coe_file} {
    set metadata [dict create]
    
    if {![file exists $coe_file]} {
        puts "Error: COE file not found: $coe_file"
        return $metadata
    }
    
    puts "Parsing metadata from: [file tail $coe_file]"
    
    set fp [open $coe_file r]
    set content [read $fp]
    close $fp
    
    # Parse metadata from comments
    foreach line [split $content "\n"] {
        set line [string trim $line]
        
        # Extract shape information (weights format)
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
            puts "  Shape: ($shape_str)"
        }
        
        # Alternative shape format (biases format)
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
            puts "  Shape: ($shape_str)"
        }
        
        # Extract total elements
        if {[regexp {Total elements:\s*(\d+)} $line -> total]} {
            dict set metadata total_elements $total
            puts "  Total elements: $total"
        }
        
        # Extract layer type
        if {[regexp {Layer (\d+):\s*(\w+)} $line -> layer_num layer_type]} {
            dict set metadata layer_number $layer_num
            dict set metadata layer_type $layer_type
            puts "  Layer: $layer_num ($layer_type)"
        }
        
        # Extract quantization info
        if {[regexp {Quantization:\s*(\d+) fractional bits} $line -> frac_bits]} {
            dict set metadata frac_bits $frac_bits
            puts "  Quantization: Q1.$frac_bits"
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
    
    puts "\nCalculating memory parameters for $memory_type:"
    puts "  Shape list: $shape_list"
    
    if {$memory_type == "weights"} {
        # For weights: shape is (kernel_h, kernel_w, in_channels, num_filters)
        # Memory organization: depth = kernel_h * kernel_w
        #                      width = num_filters * 8 bits
        if {[llength $shape_list] != 4} {
            puts "Error: Expected 4D shape for weights, got [llength $shape_list]D"
            return $params
        }
        
        set kernel_h [lindex $shape_list 0]
        set kernel_w [lindex $shape_list 1]
        set in_channels [lindex $shape_list 2]
        set num_filters [lindex $shape_list 3]
        
        set depth [expr {$kernel_h * $kernel_w}]
        set width [expr {$num_filters * 8}]
        
        puts "  Kernel size: ${kernel_h}x${kernel_w}"
        puts "  Input channels: $in_channels"
        puts "  Number of filters: $num_filters"
        puts "  → Memory depth: $depth addresses"
        puts "  → Memory width: $width bits"
        
        dict set params depth $depth
        dict set params width $width
        dict set params description "Weights: ${kernel_h}x${kernel_w} kernel, ${num_filters} filters"
        
    } elseif {$memory_type == "bias"} {
        # For biases: shape is (num_filters,)
        # Memory organization: depth = 1 (single wide word)
        #                      width = num_filters * 8 bits (all biases packed together)
        if {[llength $shape_list] != 1} {
            puts "Error: Expected 1D shape for biases, got [llength $shape_list]D"
            return $params
        }
        
        set num_filters [lindex $shape_list 0]
        
        set depth 1
        set width [expr {$num_filters * 8}]
        
        puts "  Number of filters: $num_filters"
        puts "  → Memory depth: $depth addresses"
        puts "  → Memory width: $width bits"
        
        dict set params depth $depth
        dict set params width $width
        dict set params description "Biases: ${num_filters} filters"
    }
    
    return $params
}

# ============================================================================
# Search for COE files
# ============================================================================
puts "\n=== Searching for COE Files ==="

set coe_search_dirs [list \
    "./model/fpga_weights_and_bias" \
    "../model/fpga_weights_and_bias" \
    "./model" \
    "../model" \
    ".." \
]

set found_coe_files [list]

foreach search_dir $coe_search_dirs {
    if {[file isdirectory $search_dir]} {
        puts "Searching in: $search_dir"
        set coe_files [glob -nocomplain "$search_dir/*.coe"]
        foreach coe_file $coe_files {
            set normalized_path [file normalize $coe_file]
            if {[lsearch $found_coe_files $normalized_path] == -1} {
                lappend found_coe_files $normalized_path
                puts "  ✓ Found: [file tail $coe_file]"
            }
        }
    }
}

if {[llength $found_coe_files] == 0} {
    puts "\n✗ ERROR: No COE files found!"
    puts "Searched in: $coe_search_dirs"
    puts "\nPlease generate COE files using your Python model script first."
    exit 1
}

puts "\n✓ Found [llength $found_coe_files] COE file(s) total"

# ============================================================================
# Organize COE files by type
# ============================================================================
puts "\n=== Organizing COE Files ==="

set weights_files [list]
set bias_files [list]

foreach coe_file $found_coe_files {
    set filename [file tail $coe_file]
    
    if {[string match "*weight*" $filename]} {
        lappend weights_files $coe_file
        puts "Weight file: $filename"
    } elseif {[string match "*bias*" $filename]} {
        lappend bias_files $coe_file
        puts "Bias file: $filename"
    } else {
        puts "Unknown type: $filename (skipping)"
    }
}
proc create_bram_ip {ip_name width depth coe_file output_dir {description "Block RAM"}} {
    puts "\n=== Creating IP: $ip_name ==="
    puts "Description: $description"
    puts "Width: $width bits"
    puts "Depth: $depth words"
    puts "COE file: $coe_file"
    
    # Calculate address width (ceiling of log2(depth))
    set addr_width [expr {int(ceil(log($depth)/log(2)))}]
    puts "Address width: $addr_width bits"
    
    # Create output directory for this IP
    set ip_dir "$output_dir/$ip_name"
    file mkdir $ip_dir
    
    # Create the IP
    if {[catch {
        # Create Block Memory Generator IP
        create_ip -name blk_mem_gen \
                  -vendor xilinx.com \
                  -library ip \
                  -version 8.4 \
                  -module_name $ip_name \
                  -dir $ip_dir
        
        # Configure the IP properties
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
            CONFIG.Port_A_Clock {100} \
            CONFIG.Port_A_Write_Rate {0} \
            CONFIG.Port_A_Enable_Rate {100} \
            CONFIG.Algorithm {Minimum_Area} \
        ] [get_ips $ip_name]
        
        puts "✓ IP configuration complete"
        
        # Generate IP output products
        puts "Generating IP output products..."
        generate_target all [get_files $ip_dir/$ip_name.xci]
        
        # Create wrapper/synthesis files
        puts "Creating synthesis files..."
        create_ip_run [get_files $ip_dir/$ip_name.xci]
        
        puts "✓ IP $ip_name created successfully at: $ip_dir"
        return 1
        
    } result]} {
        puts "✗ Failed to create IP $ip_name: $result"
        return 0
    }
}

# ============================================================================
# Create the Memory IPs from discovered COE files
# ============================================================================

puts "\n=========================================="
puts "Creating Memory IPs"
puts "=========================================="

set created_ips [list]

# Process weight files
foreach coe_file $weights_files {
    puts "\n--- Processing Weight File: [file tail $coe_file] ---"
    
    # Parse metadata
    set metadata [parse_coe_metadata $coe_file]
    
    if {![dict exists $metadata layer_number]} {
        puts "Warning: Could not determine layer number, skipping"
        continue
    }
    
    set layer_num [dict get $metadata layer_number]
    set ip_name "conv${layer_num}_mem_weights"
    
    # Calculate memory parameters
    set params [calculate_memory_params $metadata "weights"]
    
    if {[dict size $params] == 0} {
        puts "Error: Could not calculate memory parameters"
        continue
    }
    
    set width [dict get $params width]
    set depth [dict get $params depth]
    set desc [dict get $params description]
    
    # Create IP
    if {[create_bram_ip $ip_name $width $depth $coe_file $ip_output_dir $desc]} {
        lappend created_ips $ip_name
    }
}

# Process bias files
foreach coe_file $bias_files {
    puts "\n--- Processing Bias File: [file tail $coe_file] ---"
    
    # Parse metadata
    set metadata [parse_coe_metadata $coe_file]
    
    if {![dict exists $metadata layer_number]} {
        puts "Warning: Could not determine layer number, skipping"
        continue
    }
    
    set layer_num [dict get $metadata layer_number]
    set ip_name "conv${layer_num}_mem_bias"
    
    # Calculate memory parameters
    set params [calculate_memory_params $metadata "bias"]
    
    if {[dict size $params] == 0} {
        puts "Error: Could not calculate memory parameters"
        continue
    }
    
    set width [dict get $params width]
    set depth [dict get $params depth]
    set desc [dict get $params description]
    
    # Create IP
    if {[create_bram_ip $ip_name $width $depth $coe_file $ip_output_dir $desc]} {
        lappend created_ips $ip_name
    }
}

# ============================================================================
# Summary
# ============================================================================

puts "\n=========================================="
puts "IP Creation Summary"
puts "=========================================="

puts "\nProcessed [llength $found_coe_files] COE file(s)"
puts "Created [llength $created_ips] IP(s):"

foreach ip $created_ips {
    puts "  ✓ $ip"
}

if {[llength $created_ips] > 0} {
    puts "\n✓ All memory IPs created successfully!"
    puts "\nMemory Organization:"
    puts "  - Weights: N addresses × W bits"
    puts "    • Address = kernel_row * kernel_width + kernel_col"
    puts "    • Each address contains weights for all filters"
    puts ""
    puts "  - Biases: 1 address × W bits"
    puts "    • Single address contains all bias values"
    puts ""
    puts "IP files created in: $ip_output_dir"
    puts "\nNext steps:"
    puts "  1. Add these IPs to your Vivado project"
    puts "  2. Instantiate them in your memory controllers"
    puts "  3. Run synthesis and implementation"
} else {
    puts "\n✗ No IPs were created. Check errors above."
    exit 1
}

puts "=========================================="
