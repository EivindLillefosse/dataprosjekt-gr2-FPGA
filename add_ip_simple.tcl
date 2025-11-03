# Open the existing project
open_project VGA_prosjekt.xpr

# Add the IP XCI file to the project sources
set ip_file "VGA_prosjekt.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci"
add_files -fileset sources_1 $ip_file

# Set properties for synthesis and implementation
set_property used_in_synthesis true [get_files $ip_file]
set_property used_in_implementation true [get_files $ip_file]

# Save project
save_project
close_project

puts "IP added to project sources successfully!"