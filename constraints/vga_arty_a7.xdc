## Arty A7-100T Constraints for VGA Display via Pmod VGA
## Pmod VGA uses 12-bit color (4R, 4G, 4B) + HSYNC + VSYNC
## Connected to Pmod Port JA (change to JB/JC/JD if using different port)

## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## Reset button (active high) - using BTN0
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { rst }];

## Pmod Header JA - VGA Signals
## JA1-JA4 (top row) and JA7-JA10 (bottom row)
## Pmod VGA pinout:
##   JA1  = RED0    (LSB of red)
##   JA2  = RED1
##   JA3  = RED2
##   JA4  = RED3    (MSB of red)
##   JA7  = GREEN0  (LSB of green)
##   JA8  = GREEN1
##   JA9  = GREEN2
##   JA10 = GREEN3  (MSB of green)
## Pmod Header JB - VGA Signals (continued)
##   JB1  = BLUE0   (LSB of blue)
##   JB2  = BLUE1
##   JB3  = BLUE2
##   JB4  = BLUE3   (MSB of blue)
##   JB7  = HSYNC
##   JB8  = VSYNC

## VGA Red[3:0] - Pmod JA pins 1-4 (top row)
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[0] }]; #JA1
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[1] }]; #JA2
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[2] }]; #JA3
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[3] }]; #JA4

## VGA Green[3:0] - Pmod JA pins 7-10 (bottom row)
set_property -dict { PACKAGE_PIN D13   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[0] }]; #JA7
set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[1] }]; #JA8
set_property -dict { PACKAGE_PIN A18   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[2] }]; #JA9
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[3] }]; #JA10

## VGA Blue[3:0] - Pmod JB pins 1-4 (top row)
set_property -dict { PACKAGE_PIN E15   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[0] }]; #JB1
set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[1] }]; #JB2
set_property -dict { PACKAGE_PIN D15   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[2] }]; #JB3
set_property -dict { PACKAGE_PIN C15   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[3] }]; #JB4

## VGA Sync signals - Pmod JB pins 7-8 (bottom row)
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { VGA_HS_O }]; #JB7
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { VGA_VS_O }]; #JB8

## SPI Signals - Pmod JC
## Using Pmod JC for SPI interface
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { SCLK }];  #JC1
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { MOSI }];  #JC2
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { MISO }];  #JC3
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { CS_N }];  #JC4

## Configuration options
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
