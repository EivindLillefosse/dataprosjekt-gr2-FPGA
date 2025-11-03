## Constraint file for arty_spi_top module
## This file maps the arty_spi_top.vhd entity ports to Arty A7 board pins
## Target: Arty A7-35T / A7-100T

## FPGA Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## System Clock (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk100 }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk100 }];

## Reset Button (btn[0] - active high)
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { btn_reset }];

## Switches (sw[3:0])
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];

## SPI Interface - Pmod Header JA
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { spi_ss_n }];  # JA[1]
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { spi_sclk }];  # JA[2]
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { spi_mosi }];  # JA[3]
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { spi_miso }];  # JA[4]

## LEDs - Display received data (lower 4 bits)
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## RGB LED0 - Status indicators
set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { led0_b }];
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { led0_g }];
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { led0_r }];

## RGB LED1 - Upper data bits (bits 4-6)
set_property -dict { PACKAGE_PIN G4    IOSTANDARD LVCMOS33 } [get_ports { led1_b }];
set_property -dict { PACKAGE_PIN J4    IOSTANDARD LVCMOS33 } [get_ports { led1_g }];
set_property -dict { PACKAGE_PIN G3    IOSTANDARD LVCMOS33 } [get_ports { led1_r }];

## RGB LED2 - MSB and ACK
set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports { led2_b }];
set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { led2_g }];
set_property -dict { PACKAGE_PIN J3    IOSTANDARD LVCMOS33 } [get_ports { led2_r }];

## Timing Constraints
## SPI clock domain - 1 MHz SPI clock
create_clock -add -name spi_clk -period 1000.00 -waveform {0 500} [get_ports { spi_sclk }];

## Set false paths between asynchronous clock domains
set_false_path -from [get_clocks sys_clk_pin] -to [get_clocks spi_clk]
set_false_path -from [get_clocks spi_clk] -to [get_clocks sys_clk_pin]