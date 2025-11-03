# Open the existing project
open_project VGA_prosjekt.xpr

# Try to run synthesis and let Vivado handle IP automatically
launch_runs synth_1 -jobs 4

# Don't wait, just save and exit
save_project
close_project

puts "Main synthesis launched!"