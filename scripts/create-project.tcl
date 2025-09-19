# Create project with optional command-line parameters
# Usage: vivado -mode batch -source create-project.tcl -tclargs [part_number] [top_module] [project_name]
# Example: vivado -mode batch -source create-project.tcl -tclargs XC7A100TCSG324-1 my_top MyProject

# Set default values
set project_name "CNN"
set project_dir "./vivado_project"
set part_number "XC7A35TICSG324-1L"
set top_module "top"

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

# Set top module
set_property top $top_module [current_fileset]
