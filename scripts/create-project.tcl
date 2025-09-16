# Set project name and directory
set project_name "CNN"
set project_dir "./vivado_project"

# Create the project
create_project $project_name $project_dir -part XC7A35TICSG324-1L -force

# Start GUI
start_gui

# Add VHDL source files from src directory (recursively)
set src_dir "./src"
# First add non-testbench files directly in src directory
foreach file [glob -nocomplain "$src_dir/*.vhd"] {
    if {![string match "*_tb.vhd" $file]} {
        add_files $file
    }
}
# Then add non-testbench files in subdirectories (level 1)
foreach subdir [glob -nocomplain -type d "$src_dir/*"] {
    foreach file [glob -nocomplain "$subdir/*.vhd"] {
        if {![string match "*_tb.vhd" $file]} {
            add_files $file
        }
    }
}
# Then add non-testbench files in subdirectories (level 2)
foreach subdir [glob -nocomplain -type d "$src_dir/*"] {
    foreach subsubdir [glob -nocomplain -type d "$subdir/*"] {
        foreach file [glob -nocomplain "$subsubdir/*.vhd"] {
            if {![string match "*_tb.vhd" $file]} {
                add_files $file
            }
        }
    }
}

# Add testbench files from src directory to simulation fileset
foreach file [glob -nocomplain "$src_dir/*_tb.vhd"] {
    add_files -fileset sim_1 $file
}
# Add testbench files from subdirectories to simulation fileset (level 1)
foreach subdir [glob -nocomplain -type d "$src_dir/*"] {
    foreach file [glob -nocomplain "$subdir/*_tb.vhd"] {
        add_files -fileset sim_1 $file
    }
}
# Add testbench files from subdirectories to simulation fileset (level 2)
foreach subdir [glob -nocomplain -type d "$src_dir/*"] {
    foreach subsubdir [glob -nocomplain -type d "$subdir/*"] {
        foreach file [glob -nocomplain "$subsubdir/*_tb.vhd"] {
            add_files -fileset sim_1 $file
        }
    }
}

# Add constraint files from constraints directory
set constraints_dir "./constraints"
foreach xdc_file [glob -nocomplain "$constraints_dir/*.xdc"] {
    add_files -fileset constrs_1 $xdc_file
}

# Set top module (replace with your actual top-level entity name)
set_property top top [current_fileset]
