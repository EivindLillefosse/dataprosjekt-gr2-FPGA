# Set project name and directory
set project_name "CNN"
set project_dir "./vivado_project"

# Create the project
create_project $project_name $project_dir -part xc7z020clg400-1 -force

# Start GUI
start_gui

# Add VHDL source files from src directory
set src_dir "./src"
foreach file [glob -nocomplain "$src_dir/*.vhd"] {
    add_files $file
}

# Add constraint files from constraints directory
set constraints_dir "./constraints"
foreach xdc_file [glob -nocomplain "$constraints_dir/*.xdc"] {
    add_files -fileset constrs_1 $xdc_file
}

# Set top module (replace with your actual top-level entity name)
set_property top top [current_fileset]
