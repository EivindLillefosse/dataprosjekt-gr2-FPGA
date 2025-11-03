# Open the existing project
open_project VGA_prosjekt.xpr

# Add the IP XCI file to the project sources if not already there
set ip_file "VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci"
if {[file exists $ip_file]} {
    # Remove it first if it exists to avoid duplicates
    catch {remove_files $ip_file}
    
    # Add the IP file to sources
    add_files -fileset sources_1 $ip_file
    
    # Set properties for the IP
    set_property used_in_synthesis true [get_files $ip_file]
    set_property used_in_implementation true [get_files $ip_file]
    set_property generate_synth_checkpoint true [get_files $ip_file]
    
    puts "IP file added to project: $ip_file"
} else {
    puts "ERROR: IP file not found: $ip_file"
}

# Generate all targets for the IP
generate_target all [get_files $ip_file]

# Create IP synthesis run if it doesn't exist
catch {create_ip_run [get_files $ip_file]}

# Launch IP synthesis
if {[get_runs clk_wiz_0_synth_1] != ""} {
    launch_runs clk_wiz_0_synth_1 -jobs 4
    wait_on_run clk_wiz_0_synth_1
    puts "IP synthesis completed"
}

# Reset implementation to ensure clean build
reset_run impl_1

# Save project
save_project
close_project

puts "IP properly integrated into project!"