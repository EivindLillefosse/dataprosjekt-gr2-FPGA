# Create project with optional command-line parameters
# Usage:
#   With GUI: vivado -source create-project.tcl -tclargs [part_number] [top_module] [project_name]
#   Batch mode: vivado -mode batch -source create-project.tcl -tclargs [part_number] [top_module] [project_name]
# Example: vivado -source create-project.tcl -tclargs 100 top my_proj

# Set default values
set project_name "CNN"
set project_dir "./vivado_project"
set part_number "XC7A100TCSG324-1"
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

# Ensure Vivado treats VHDL sources as VHDL-2008 (XSIM does not support 2019)
puts "\nSetting VHDL standard to 2008 for all VHDL files..."
foreach vfile [get_files_recursive $src_dir "*.vhd"] {
    if {[catch {set_property FILE_TYPE {VHDL 2008} [get_files $vfile]} err]} {
        puts "Warning: failed to set FILE_TYPE for $vfile : $err"
    } else {
        puts "  Set VHDL 2008 for: $vfile"
    }
}

# Ensure Vivado treats VHDL sources as VHDL-2008 (XSIM does not support 2019)
puts "\nSetting VHDL standard to 2008 for all VHDL files..."
foreach vfile [get_files_recursive $src_dir "*.vhd"] {
    if {[catch {set_property FILE_TYPE {VHDL 2008} [get_files $vfile]} err]} {
        puts "Warning: failed to set FILE_TYPE for $vfile : $err"
    } else {
        puts "  Set VHDL 2008 for: $vfile"
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

    # Single-pass, case-insensitive parsing of relevant metadata
    foreach line [split $content "\n"] {
        set l [string trim $line]
        if {$l == ""} continue

        # Shape: Original shape: (3, 3, 1, 8)
        if {[regexp -nocase {Original shape:\s*\(([^)]+)\)} $l -> shape_str]} {
            dict set metadata shape $shape_str
            set shape_values [split $shape_str ","]
            set cleaned_values {}
            foreach val $shape_values { lappend cleaned_values [string trim $val] }
            dict set metadata shape_list $cleaned_values
            continue
        }

        # Alternate shape line
        if {[regexp -nocase {Shape:\s*\(([^)]+)\)} $l -> shape_str2]} {
            dict set metadata shape $shape_str2
            set shape_values [split $shape_str2 ","]
            set cleaned_values {}
            foreach val $shape_values { lappend cleaned_values [string trim $val] }
            dict set metadata shape_list $cleaned_values
            continue
        }

        # Total elements
        if {[regexp -nocase {Total elements:\s*(\d+)} $l -> total]} {
            dict set metadata total_elements $total
            continue
        }

        # Layer / layer type
        if {[regexp -nocase {Layer\s*(\d+):\s*([A-Za-z0-9_]+)} $l -> layer_num layer_type]} {
            dict set metadata layer_number $layer_num
            dict set metadata layer_type $layer_type
            continue
        }

        # Packed width: e.g. "64 bits (packed)" or fallback "64 bits"
        if {![dict exists $metadata packed_width] && [regexp -nocase {([0-9]+)\s*bits\s*\(packed\)} $l -> pb]} {
            dict set metadata packed_width $pb
            continue
        }
        if {![dict exists $metadata packed_width] && [regexp -nocase {([0-9]+)\s*bits} $l -> pbf]} {
            dict set metadata packed_width $pbf
            # don't continue; allow packed_count detection below
        }

        # Packed count: "Each address contains all 8 filter weights" or "contains 16 values"
        if {![dict exists $metadata packed_count] && [regexp -nocase {Each address contains(?: all)?\s+([0-9]+)\s+(?:filter weights|filter|weights|values)} $l -> pc]} {
            dict set metadata packed_count $pc
            continue
        }
        if {![dict exists $metadata packed_count] && [regexp -nocase {contains(?: all)?\s+([0-9]+)\s+(?:weights|values|filter)} $l -> pc2]} {
            dict set metadata packed_count $pc2
            continue
        }
    }

    # If packed_width present but packed_count missing, try to infer packed_count from shape_list
    if {[dict exists $metadata packed_width] && ![dict exists $metadata packed_count] && [dict exists $metadata shape_list]} {
        set shape_list [dict get $metadata shape_list]
        set nd [llength $shape_list]
        if {$nd >= 4} {
            # conv: (kh, kw, in_ch, num_filters) -> pack num_filters
            set inferred [lindex $shape_list 3]
        } elseif {$nd == 3} {
            set inferred [lindex $shape_list end]
        } else {
            set inferred 1
        }
        dict set metadata packed_count $inferred
        puts "parse_coe_metadata: inferred packed_count=$inferred from shape_list"
    }

    # Debug print of parsed metadata
    if {[dict size $metadata] > 0} {
        puts "parse_coe_metadata: Parsed metadata for $coe_file -> [dict get $metadata shape] total_elements=[dict get $metadata total_elements] packed_width=[expr {[dict exists $metadata packed_width] ? [dict get $metadata packed_width] : "N/A"}] packed_count=[expr {[dict exists $metadata packed_count] ? [dict get $metadata packed_count] : "N/A"} ]"
    } else {
        puts "parse_coe_metadata: No metadata parsed from $coe_file"
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
        # Default: Use 8-bit width for weights (Q1.6 / 8-bit signed storage).
        # Store one weight per address (unpacked), so depth = total_elements.
        set width 8
        set depth $total_elements

        # If COE metadata indicates packed memory organization, use that
        if {[dict exists $metadata packed_width]} {
            set width [dict get $metadata packed_width]
            # If packed_count provided, use it. Otherwise try to infer from shape_list.
            if {[dict exists $metadata packed_count]} {
                set packed_count [dict get $metadata packed_count]
            } else {
                # For conv weights shape (kh, kw, in_ch, num_filters) it's common to pack all filters per address
                if {$num_dims >= 4} {
                    set packed_count [lindex $shape_list 3]
                } elseif {$num_dims == 3} {
                    # maybe (in_ch, num_filters, ) or (kh, kw, in_ch)
                    set packed_count [lindex $shape_list end]
                } else {
                    set packed_count 1
                }
                puts "Inferred packed_count=$packed_count from shape_list"
            }
            # depth = ceil(total_elements / packed_count)
            set depth [expr {int(ceil($total_elements / double($packed_count)))}]
            puts "Detected/Infered packed COE: packed_width=$width, per_address=$packed_count -> depth=$depth"
        }

        if {$layer_type == "dense"} {
            set input_dim [lindex $shape_list 0]
            set output_dim [lindex $shape_list 1]
            puts "Calculated depth: $depth, width: $width for dense weights (unpacked)"
            puts "  Input dim: $input_dim, Output dim: $output_dim, Total elements: $total_elements"
            dict set params depth $depth
            dict set params width $width
            dict set params description "Dense (unpacked 8-bit): ${input_dim}x${output_dim} weights"
        } else {
            # Conv layer weights: shape is (kernel_h, kernel_w, in_channels, num_filters)
            set kernel_h [lindex $shape_list 0]
            set kernel_w [lindex $shape_list 1]
            set in_ch [lindex $shape_list 2]
            set num_filters [lindex $shape_list 3]
            puts "Calculated depth: $depth, width: $width for conv weights (unpacked)"
            puts "  Kernel: ${kernel_h}x${kernel_w}, In channels: ${in_ch}, Filters: ${num_filters}, Total elements: $total_elements"
            dict set params depth $depth
            dict set params width $width
            dict set params description "Conv weights (unpacked 8-bit): ${kernel_h}x${kernel_w} kernel, ${num_filters} filters"
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

# Cleanup existing ip_repo contents to avoid stale/old IP cores being reused.
# This deletes files and directories inside ./ip_repo but does not delete the ip_repo
# directory itself. We print what we removed for traceability.
set ip_repo_dir "./ip_repo"
if {[file isdirectory $ip_repo_dir]} {
    puts "\n=== Cleaning existing IP repository: $ip_repo_dir ==="
    # Collect entries first to avoid modifying the list while iterating
    set entries [glob -nocomplain -directory $ip_repo_dir "*"]
    if {[llength $entries] == 0} {
        puts "  (no files to remove)"
    } else {
        foreach e $entries {
            set full [file normalize $e]
            if {[catch {file delete -force $full} delerr]} {
                puts "  Warning: failed to remove $full : $delerr"
            } else {
                puts "  Removed: $full"
            }
        }
    }
    puts "=== IP repository cleanup complete ===\n"
}

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
                puts "Skipping - IP $ip_name already exists"
            }
        }
    }
}

# Generate IP output products
puts "\n=== Generating IP Output Products ==="
set all_ips [get_ips]
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

# ============================================================================
# Create IPs from YAML manifests
# ============================================================================
puts "\n=== Creating IPs from YAML Manifests ==="
set manifests_dir "./scripts/ip_manifests"

if {[file isdirectory $manifests_dir]} {
    set yaml_files [glob -nocomplain "$manifests_dir/*.yaml"]

    if {[llength $yaml_files] == 0} {
        puts "No YAML manifest files found in $manifests_dir"
    } else {
        puts "Found [llength $yaml_files] YAML manifest file(s)"

        foreach yaml_file $yaml_files {
            puts "\n--- Processing manifest: [file tail $yaml_file] ---"

            # Parse YAML file
            set fp [open $yaml_file r]
            set yaml_content [read $fp]
            close $fp

            # Extract IP ID and configuration
            set ip_id ""
            set config_dict [dict create]

            # Parse YAML (simple parser for our structured format)
            set metadata_dict [dict create]
            set in_metadata 0
            set in_config 0

            foreach line [split $yaml_content "\n"] {
                set orig_line $line
                set line [string trim $line]

                # Skip comments and empty lines
                if {[string match "#*" $line] || $line == ""} {
                    continue
                }

                # Extract IP ID
                if {[regexp {^id:\s*(.+)$} $line -> id_value]} {
                    set ip_id [string trim $id_value]
                    puts "  IP ID: $ip_id"
                    continue
                }

                # Detect metadata section
                if {[regexp {^metadata:\s*$} $line]} {
                    set in_metadata 1
                    set in_config 0
                    puts "  Debug: Entered metadata section"
                    continue
                }

                # Detect config section
                if {[regexp {^config:\s*$} $line]} {
                    set in_config 1
                    set in_metadata 0
                    puts "  Debug: Entered config section (metadata had [dict size $metadata_dict] entries)"
                    continue
                }

                # Parse metadata entries (indented under metadata:) - check BEFORE trimming
                if {$in_metadata && [regexp {^\s+([^:]+):\s*(.+)$} $orig_line -> meta_key meta_value]} {
                    set meta_key [string trim $meta_key]
                    set meta_value [string trim $meta_value "\""]
                    puts "  Debug: Parsed metadata: $meta_key = $meta_value"
                    dict set metadata_dict $meta_key $meta_value
                    continue
                }

                # Extract configuration parameters (indented under config:) - check BEFORE trimming
                if {$in_config && [regexp {^\s*CONFIG\.([^:]+):\s*(.+)$} $orig_line -> param_name param_value]} {
                    set param_name [string trim $param_name]
                    set param_value [string trim $param_value]

                    # Remove quotes if present
                    set param_value [string trim $param_value "\""]

                    # Convert boolean strings to Tcl boolean values
                    if {$param_value == "true"} {
                        set param_value true
                    } elseif {$param_value == "false"} {
                        set param_value false
                    }

                    dict set config_dict $param_name $param_value
                }
            }

            # Create IP if we have valid ID and config
            if {$ip_id != "" && [dict size $config_dict] > 0} {
                puts "  Creating IP: $ip_id with [dict size $config_dict] configuration parameters"

                # Extract IP core name from Component_Name or derive from id
                set component_name $ip_id
                if {[dict exists $config_dict Component_Name]} {
                    set component_name [dict get $config_dict Component_Name]
                }

                # ============================================================
                # UNIVERSAL IP DETECTION - Uses metadata from YAML manifest
                # ============================================================
                set ip_name ""
                set ip_vendor "xilinx.com"
                set ip_library "ip"
                set ip_version ""

                # STRATEGY 0: Use metadata from YAML (BEST - no guessing!)
                puts "  Debug: metadata_dict has [dict size $metadata_dict] entries"
                if {[dict size $metadata_dict] > 0} {
                    puts "  Debug: metadata keys: [dict keys $metadata_dict]"
                }

                if {[dict exists $metadata_dict name]} {
                    set ip_name [dict get $metadata_dict name]
                    puts "  ✓ IP name from metadata: $ip_name"
                }
                if {[dict exists $metadata_dict vendor]} {
                    set ip_vendor [dict get $metadata_dict vendor]
                    puts "  ✓ IP vendor from metadata: $ip_vendor"
                }
                if {[dict exists $metadata_dict library]} {
                    set ip_library [dict get $metadata_dict library]
                }
                if {[dict exists $metadata_dict version]} {
                    set ip_version [dict get $metadata_dict version]
                    puts "  ✓ IP version from metadata: $ip_version"
                }

                # If metadata provided complete info, we're done!
                if {$ip_name != "" && $ip_version != ""} {
                    puts "  ✓ Using metadata: $ip_vendor:$ip_library:$ip_name:$ip_version"
                } else {
                    # Fallback to smart detection if metadata incomplete
                    puts "  Metadata incomplete, attempting smart detection..."

                    # Strategy 1: Detect from Memory_Type (Block RAM Generator)
                    if {$ip_name == "" && [dict exists $config_dict Memory_Type]} {
                        set ip_name "blk_mem_gen"
                        # Query available versions from catalog
                        set catalog_info [get_ipdefs -filter {NAME == blk_mem_gen}]
                        if {[llength $catalog_info] > 0} {
                            set ip_version [get_property VERSION [lindex $catalog_info 0]]
                            puts "  Detected Block Memory Generator v$ip_version from Memory_Type property"
                        } else {
                            # Fallback if catalog query fails
                            set ip_version "8.4"
                            puts "  Detected Block Memory Generator (using fallback version $ip_version)"
                        }
                    }

                    # Strategy 2: Detect from Interface_Type (FIFO Generator)
                    if {$ip_name == "" && [dict exists $config_dict INTERFACE_TYPE]} {
                        set interface_type [dict get $config_dict INTERFACE_TYPE]
                        if {[string match "*FIFO*" $interface_type] ||
                            [dict exists $config_dict Fifo_Implementation]} {
                            set ip_name "fifo_generator"
                            # Query available versions from catalog
                            set catalog_info [get_ipdefs -filter {NAME == fifo_generator}]
                            if {[llength $catalog_info] > 0} {
                                set ip_version [get_property VERSION [lindex $catalog_info 0]]
                                puts "  Detected FIFO Generator v$ip_version from Interface_Type property"
                            } else {
                                # Fallback if catalog query fails
                                set ip_version "13.2"
                                puts "  Detected FIFO Generator (using fallback version $ip_version)"
                            }
                        }
                    }

                    # Strategy 3: Pattern matching on Component_Name (legacy support)
                    if {$ip_name == "" && [dict exists $config_dict Component_Name]} {
                        set comp_name [dict get $config_dict Component_Name]
                        if {[regexp {^(fifo_generator|blk_mem_gen)_.*} $comp_name -> core_name]} {
                            set ip_name $core_name
                            # Query version from catalog
                            set catalog_info [get_ipdefs -filter "NAME == $ip_name"]
                            if {[llength $catalog_info] > 0} {
                                set ip_version [get_property VERSION [lindex $catalog_info 0]]
                                puts "  Detected $ip_name v$ip_version from component name pattern"
                            }
                        }
                    }

                    # Strategy 4: Universal fallback - try to find any matching IP in catalog
                    if {$ip_name == ""} {
                        puts "  Attempting universal IP detection for: $ip_id"

                        # Try to find IP by searching catalog with component name keywords
                        set search_keywords [list]
                        if {[dict exists $config_dict Component_Name]} {
                            set comp_name [dict get $config_dict Component_Name]
                            # Extract potential keywords from component name
                            foreach word [split $comp_name "_"] {
                                if {[string length $word] > 3} {
                                    lappend search_keywords $word
                                }
                            }
                        }

                        # Search IP catalog for matching definitions
                        foreach keyword $search_keywords {
                            set matching_ipdefs [get_ipdefs -filter "NAME =~ *$keyword*"]
                            if {[llength $matching_ipdefs] > 0} {
                                set ipdef [lindex $matching_ipdefs 0]
                                set ip_name [get_property NAME $ipdef]
                                set ip_version [get_property VERSION $ipdef]
                                set ip_vendor [get_property VENDOR $ipdef]
                                set ip_library [get_property LIBRARY $ipdef]
                                puts "  ✓ Found matching IP in catalog: $ip_vendor:$ip_library:$ip_name:$ip_version"
                                break
                            }
                        }
                    }
                }

                if {$ip_name == ""} {
                    puts "  ✗ Warning: Could not determine IP type for $ip_id (Component_Name: $component_name)"
                    puts "     Available CONFIG properties: [dict keys $config_dict]"
                    puts "     Consider adding specific detection logic for this IP type"
                    continue
                }

                # Check if IP already exists
                if {[dict exists $created_ips $component_name]} {
                    puts "  IP $component_name already exists, skipping"
                    continue
                }

                # Create the IP
                set create_result [catch {
                    create_ip -name $ip_name \
                        -vendor $ip_vendor \
                        -library $ip_library \
                        -version $ip_version \
                        -module_name $component_name \
                        -dir ./ip_repo
                } create_err]

                if {$create_result != 0} {
                    puts "  ✗ Failed to create IP $component_name: $create_err"
                    continue
                }

                puts "  ✓ IP core created: $component_name"

                # Apply configuration properties
                set ip_obj [get_ips $component_name]
                set config_list [list]

                dict for {param_name param_value} $config_dict {
                    lappend config_list "CONFIG.$param_name" $param_value
                }

                if {[llength $config_list] > 0} {
                    set config_result [catch {
                        set_property -dict $config_list $ip_obj
                    } config_err]

                    if {$config_result != 0} {
                        puts "  Warning: Some configuration parameters failed: $config_err"
                    } else {
                        puts "  ✓ Configuration applied successfully"
                    }
                }

                # Mark as created
                dict set created_ips $component_name 1

            } else {
                puts "  Warning: Invalid manifest file (missing ID or config)"
            }
        }

        # Generate output products for all newly created IPs from YAML
        puts "\n=== Generating Output Products for YAML-based IPs ==="
        set all_current_ips [get_ips]
        if {[llength $all_current_ips] > 0} {
            foreach ip $all_current_ips {
                # Check if this IP was created from YAML manifest
                set ip_name [get_property NAME $ip]
                set should_generate false

                # Check if this IP matches any of our YAML-created IPs
                foreach yaml_file $yaml_files {
                    set fp [open $yaml_file r]
                    set yaml_content [read $fp]
                    close $fp

                    foreach line [split $yaml_content "\n"] {
                        if {[regexp {^id:\s*(.+)$} $line -> id_value]} {
                            set yaml_ip_id [string trim $id_value]
                            if {$ip_name == $yaml_ip_id} {
                                set should_generate true
                                break
                            }
                        }
                        if {[regexp {^\s*CONFIG\.Component_Name:\s*"?([^"]+)"?$} $line -> comp_name]} {
                            set yaml_comp_name [string trim $comp_name "\""]
                            if {$ip_name == $yaml_comp_name} {
                                set should_generate true
                                break
                            }
                        }
                    }
                    if {$should_generate} {break}
                }

                if {$should_generate} {
                    puts "Generating output products for: $ip_name"
                    if {[catch {generate_target all [get_files [get_property IP_FILE [get_ips $ip_name]]]} result]} {
                        puts "  Warning: Failed to generate IP $ip_name: $result"
                    } else {
                        puts "  ✓ Successfully generated IP: $ip_name"
                    }
                }
            }

            # Update compile order to include generated IP files
            update_compile_order -fileset sources_1
            puts "YAML IP generation complete."
        } else {
            puts "No IPs found to generate."
        }
    }
} else {
    puts "No IP manifest directory found at: $manifests_dir"
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