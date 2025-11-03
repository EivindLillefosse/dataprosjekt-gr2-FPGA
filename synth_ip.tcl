# Open the existing project
open_project VGA_prosjekt.xpr

# Generate all IP targets  
generate_target all [get_ips clk_wiz_0]

# Launch IP synthesis run
launch_runs clk_wiz_0_synth_1 -jobs 4

# Wait for completion with timeout
wait_on_run clk_wiz_0_synth_1

# Save the project
save_project

# Close the project  
close_project

puts "IP synthesis completed!"