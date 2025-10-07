# Arty A7-35T Constraints for SPI Demo
# Based on Arty A7 Reference Manual

## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk100 }]; #IO_L12P_T1_MRCC_35 Sch=clk100mhz
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports {clk100}];

## Reset Button (BTN0)
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { btn_reset }]; #IO_L6N_T0_VREF_16 Sch=btn[0]

## LEDs (show received SPI data - Arty A7 has 4 regular LEDs)
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; #IO_L24N_T3_35 Sch=led[0]
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; #IO_25_35 Sch=led[1]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; #IO_L24P_T3_A01_D17_14 Sch=led[2]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; #IO_L24N_T3_A00_D16_14 Sch=led[3]

## RGB LEDs (data display and status)
# RGB LED 0 (status indicators)
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { led0_r }]; #IO_L19P_T3_35 Sch=led0_r
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { led0_g }]; #IO_L19N_T3_VREF_35 Sch=led0_g  
set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { led0_b }]; #IO_L18N_T2_35 Sch=led0_b

# RGB LED 1 (data bits 4-6)
set_property -dict { PACKAGE_PIN N3    IOSTANDARD LVCMOS33 } [get_ports { led1_r }]; #IO_L12P_T1_MRCC_35 Sch=led1_r
set_property -dict { PACKAGE_PIN P1    IOSTANDARD LVCMOS33 } [get_ports { led1_g }]; #IO_L19N_T3_VREF_35 Sch=led1_g
set_property -dict { PACKAGE_PIN M3    IOSTANDARD LVCMOS33 } [get_ports { led1_b }]; #IO_L11N_T1_SRCC_35 Sch=led1_b

# RGB LED 2 (data bit 7 + ACK)  
set_property -dict { PACKAGE_PIN N2    IOSTANDARD LVCMOS33 } [get_ports { led2_r }]; #IO_L14P_T2_SRCC_35 Sch=led2_r
set_property -dict { PACKAGE_PIN N1    IOSTANDARD LVCMOS33 } [get_ports { led2_g }]; #IO_L14N_T2_SRCC_35 Sch=led2_g
set_property -dict { PACKAGE_PIN O1    IOSTANDARD LVCMOS33 } [get_ports { led2_b }]; #IO_L15N_T2_DQS_35 Sch=led2_b

## Pmod Header JA (SPI Interface)
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { spi_sclk }]; #IO_0_15 Sch=ja[1]
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { spi_mosi }]; #IO_L4P_T0_15 Sch=ja[2]
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { spi_miso }]; #IO_L4N_T0_15 Sch=ja[3]
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { spi_ss_n }]; #IO_L6P_T0_15 Sch=ja[4]

## Configuration options
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]