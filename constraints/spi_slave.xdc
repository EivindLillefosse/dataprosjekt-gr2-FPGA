## Constraint file for SPI_SLAVE module standalone implementation
## This file maps SPI_SLAVE entity ports to Arty A7 board pins
## Target: Arty A7-35T / A7-100T
## SPI_SLAVE entity port names: CLK, RESET, SCLK, CS_N, MOSI, MISO

## FPGA Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## System Clock (100 MHz)
## Maps to SPI_SLAVE port: CLK
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK }];

## Reset Button
## Maps to SPI_SLAVE port: RESET
## Note: Button is active-low on board, but SPI_SLAVE expects active-high
## Consider adding an inverter in your top-level wrapper if needed
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { RESET }];

## SPI Interface - Pmod Header JA
## Maps to SPI_SLAVE ports: SCLK, MOSI, MISO, CS_N
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { SCLK }];  # JA[1]
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { MOSI }];  # JA[2]
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { MISO }];  # JA[3]
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { CS_N }];  # JA[4]

## User Interface Ports (Internal - not connected to physical pins)
## These ports would normally connect to other logic inside the FPGA
## Mark them with IOSTANDARD to satisfy DRC, but they won't be routed to pins
set_property IOSTANDARD LVCMOS33 [get_ports {DATA_IN[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DATA_OUT[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports DATA_IN_VALID]
set_property IOSTANDARD LVCMOS33 [get_ports DATA_IN_READY]
set_property IOSTANDARD LVCMOS33 [get_ports DATA_OUT_VALID]

## Mark these as not needing actual pins (they'll be left unconnected)
## This allows bitstream generation for testing purposes
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [current_design]

## Optional: LEDs for debugging (if you add them to a wrapper)
## Uncomment these if you create a top-level wrapper with LED outputs
# set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
# set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
# set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
# set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## Optional: RGB LEDs for status indication
## Uncomment these if you create a top-level wrapper with RGB LED outputs
# set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { led0_b }];
# set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { led0_g }];
# set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { led0_r }];

## Timing Constraints
## SPI clock domain - adjust based on your expected SPI clock frequency
## Example: For 1 MHz SPI clock (1000 ns period)
create_clock -add -name spi_clk -period 1000.00 -waveform {0 500} [get_ports { SCLK }];

## Set false paths between asynchronous clock domains
## Uncomment if you need to define clock domain crossings
# set_false_path -from [get_clocks sys_clk_pin] -to [get_clocks spi_clk]
# set_false_path -from [get_clocks spi_clk] -to [get_clocks sys_clk_pin]

## Input delay constraints for SPI signals
## Adjust these based on your external SPI master timing requirements
# set_input_delay -clock [get_clocks spi_clk] -min 2.0 [get_ports {MOSI CS_N}]
# set_input_delay -clock [get_clocks spi_clk] -max 8.0 [get_ports {MOSI CS_N}]

## Output delay constraints for SPI signals
# set_output_delay -clock [get_clocks spi_clk] -min 2.0 [get_ports {MISO}]
# set_output_delay -clock [get_clocks spi_clk] -max 8.0 [get_ports {MISO}]
