## Constraint file for SPI_SLAVE_TOP wrapper module
## This file maps SPI_SLAVE_TOP entity ports to Arty A7 board pins
## Target: Arty A7-35T / A7-100T

## FPGA Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## System Clock (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK }];

## Reset Button (active-low on board, invert if needed)
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { RESET }];

## SPI Interface - Pmod Header JA
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { SCLK }];  # JA[1]
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { MOSI }];  # JA[2]
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { MISO }];  # JA[3]
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { CS_N }];  # JA[4]

## LEDs for debugging
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { LED[0] }];
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { LED[1] }];
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { LED[2] }];
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }];

## RGB LED for status indication
set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { LED0_B }];
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { LED0_G }];
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { LED0_R }];

## Timing Constraints
## SPI clock domain (1 MHz example)
create_clock -add -name spi_clk -period 1000.00 -waveform {0 500} [get_ports { SCLK }];

## Set false paths between asynchronous clock domains
set_false_path -from [get_clocks sys_clk_pin] -to [get_clocks spi_clk]
set_false_path -from [get_clocks spi_clk] -to [get_clocks sys_clk_pin]
