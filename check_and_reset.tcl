# Open the existing project
open_project VGA_prosjekt.xpr

# Check if IP synthesis is complete and DCP exists
set dcp_file "VGA_prosjekt.runs/clk_wiz_0_synth_1/clk_wiz_0.dcp"
if {[file exists $dcp_file]} {
    puts "IP synthesis DCP found: $dcp_file"
} else {
    puts "IP synthesis DCP not found, the IP may still be synthesizing"
}

# Reset synthesis run to ensure clean build
reset_run synth_1

# Save the project
save_project

# Close the project
close_project

puts "Project reset and ready for synthesis!"