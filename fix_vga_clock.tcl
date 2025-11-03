# Open the existing project
open_project VGA_prosjekt.xpr

# Remove existing IP if it exists
catch {remove_files [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ "*clk_wiz_0*"}]}

# Create new Clock Wizard IP with correct VGA timing
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0

# Configure the Clock Wizard for VGA 640x480@60Hz
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.175} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
] [get_ips clk_wiz_0]

# Generate the IP
generate_target all [get_files *.xci]

# Reset runs to ensure clean build
reset_run synth_1
reset_run impl_1

# Save the project
save_project
close_project

puts "Clock Wizard reconfigured for VGA 25.175 MHz pixel clock!"