# Arty A7-35T Constraints for SPI Demo
# Based on Arty A7 Reference Manual

## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk100 }]; #IO_L12P_T1_MRCC_35 Sch=clk100mhz
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports {clk100}];

## Reset Button (BTN0)
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { btn_reset }]; #IO_L6N_T0_VREF_16 Sch=btn[0]

## LEDs 0-7 to display 8-bit MOSI data (LED0=bit7, LED1=bit6, LED2=bit5, LED3=bit4, LED4=bit3, LED5=bit2, LED6=bit1, LED7=bit0)
## Regular LEDs (always show their natural color)
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led0 }]; #IO_L24N_T3_35 Sch=led[0] - bit7
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led1 }]; #IO_25_35 Sch=led[1] - bit6
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led2 }]; #IO_L24P_T3_A01_D17_14 Sch=led[2] - bit5
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led3 }]; #IO_L24N_T3_A00_D16_14 Sch=led[3] - bit4

## RGB LEDs using GREEN channels for LEDs 4-7 (so they appear green)
# RGB LED 0 (LD4) - GREEN channel
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { led4 }]; #RGB LED0_G as LED4 - bit3
# RGB LED 1 (LD5) - GREEN channel  
set_property -dict { PACKAGE_PIN J4    IOSTANDARD LVCMOS33 } [get_ports { led5 }]; #RGB LED1_G as LED5 - bit2
# RGB LED 2 (LD6) - GREEN channel
set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { led6 }]; #RGB LED2_G as LED6 - bit1
# RGB LED 3 (LD7) - GREEN channel
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { led7 }]; #RGB LED3_G as LED7 - bit0

## Note: All 8 LEDs now used for displaying MOSI data bits
## LED0-3: Regular LEDs (show in their default colors)
## LED4-7: RGB LEDs using GREEN channels (show as green)

## Pmod Header JA (SPI Interface) - with pullups to prevent floating when unplugged
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { spi_sclk }]; #IO_0_15 Sch=ja[1]
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { spi_mosi }]; #IO_L4P_T0_15 Sch=ja[2]
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { spi_miso }]; #IO_L4N_T0_15 Sch=ja[3] (output - no pullup)
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { spi_ss_n }]; #IO_L6P_T0_15 Sch=ja[4]

## Configuration options
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]