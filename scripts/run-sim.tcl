# Run simulation with testbench specified as parameter
# Usage: vivado -mode batch -source run-sim.tcl -tclargs <testbench_name>
# Example: vivado -mode batch -source run-sim.tcl -tclargs test_MAC_tb

# Close any currently open project to avoid conflicts
catch {close_project}

# Open the existing project
if {[file exists "./vivado_project/CNN.xpr"]} {
    open_project "./vivado_project/CNN.xpr"
    puts "Project opened successfully"
} else {
    puts "ERROR: Project file ./vivado_project/CNN.xpr not found!"
    exit 1
}

# Check if testbench name is provided as argument
if {$argc > 0} {
    set testbench_name [lindex $argv 0]
} else {
    # Default testbench if no argument provided
    set testbench_name "test_MAC_tb"
    puts "No testbench specified, using default: $testbench_name"
}

puts "Setting testbench: $testbench_name"

# Set the top module for simulation
set_property top $testbench_name [get_fileset sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Launch simulation
launch_simulation

# Add all signals to waveform
add_wave /*

# Run simulation
run 2000ns

# Save waveform database
save_wave_config simulation_waves.wcfg

puts "Simulation completed. Waveform saved to simulation_waves.wcfg"