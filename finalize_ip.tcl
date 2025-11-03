# Open the project
open_project VGA_prosjekt.xpr

# Generate targets for the IP
generate_target all [get_files VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]

# Reset runs to ensure clean build
reset_run synth_1
reset_run impl_1

# Save project
save_project
close_project

puts "IP targets generated and runs reset!"