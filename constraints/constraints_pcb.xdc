## Arty A7-100T Constraints for VGA Display via Pmod VGA
## Pmod VGA uses 12-bit color (4R, 4G, 4B) + HSYNC + VSYNC
## Connected to Pmod Port JA (change to JB/JC/JD if using different port)

## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN N12   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk]
// Declare that the clk_wiz output clock is derived from the top-level clock
// This prevents warnings about related clocks with no common primary source.
// The exact instance path may vary; adjust if Vivado reports a different pin path.
create_generated_clock -name clk_out1_clk_wiz_0 -source [get_ports { clk }] -divide_by 1 [get_pins SPI_inst/VGA_inst/clk_div_inst/inst/clk_out1]

## Reset button (active high) - using BTN0
set_property -dict { PACKAGE_PIN A13    IOSTANDARD LVCMOS33 } [get_ports { rst }];

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
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[0] }]; #JA1
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[1] }]; #JA2
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[2] }]; #JA3
set_property -dict { PACKAGE_PIN L13   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[3] }]; #JA4

## VGA Green[3:0] - Pmod JA pins 7-10 (bottom row)
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[0] }]; #JA7
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[1] }]; #JA8
set_property -dict { PACKAGE_PIN R11   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[2] }]; #JA9
set_property -dict { PACKAGE_PIN N9   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[3] }]; #JA10

## VGA Blue[3:0] - Pmod JB pins 1-4 (top row)
set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[0] }]; #JB1
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[1] }]; #JB2
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[2] }]; #JB3
set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[3] }]; #JB4

## VGA Sync signals - Pmod JB pins 7-8 (bottom row)
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { VGA_HS_O }]; #JB7
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { VGA_VS_O }]; #JB8

## SPI Signals - Pmod JC
## Using Pmod JC for SPI interface
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { SCLK }];  #JC1
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { MOSI }];  #JC2
set_property -dict { PACKAGE_PIN R5   IOSTANDARD LVCMOS33 } [get_ports { MISO }];  #JC3
set_property -dict { PACKAGE_PIN T5   IOSTANDARD LVCMOS33 } [get_ports { CS_N }];  #JC4

## LEDs - CNN Guess Visualization (4 LSBs)

## Configuration options
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]