# Open the existing project  
open_project VGA_prosjekt.xpr

# Set the IP to be synthesized out-of-context
set_property generate_synth_checkpoint true [get_files VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]

# Generate synthesis checkpoint
generate_target {synthesis} [get_files VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]

# Reset the main synthesis run
reset_run synth_1

# Save project
save_project

# Close the project
close_project

puts "IP configured for out-of-context synthesis!"