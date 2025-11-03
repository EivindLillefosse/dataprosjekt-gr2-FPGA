# Open the existing project
open_project VGA_prosjekt.xpr

# Add the IP to the project if it's not already there
set ip_file "VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci"
if {[file exists $ip_file]} {
    add_files $ip_file
    set_property used_in_synthesis true [get_files $ip_file]
    set_property used_in_implementation true [get_files $ip_file]
}

# Generate all IP targets
generate_target all [get_ips]

# Create synthesis run for the IP if it doesn't exist
catch {create_ip_run [get_ips clk_wiz_0]}

# Reset and regenerate synthesis run
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Save the project
save_project

# Close the project
close_project

puts "IP added to project and synthesized successfully!"