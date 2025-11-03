# Open the existing project
open_project VGA_prosjekt.xpr

# Force add the IP XCI file to the project  
add_files -norecurse {VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci}
set_property used_in_synthesis true [get_files {VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci}]
set_property used_in_implementation true [get_files {VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci}]

# Update compile order
update_compile_order -fileset sources_1

# Create the IP run again (force)
create_ip_run [get_files {VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci}] -force

# Reset main synthesis
reset_run synth_1

# Save project
save_project
close_project

puts "IP properly added to project sources!"