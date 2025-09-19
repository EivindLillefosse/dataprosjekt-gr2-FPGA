----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: Multiplier
-- Module Name: top - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.types_pkg.all;



entity conv_layer is
    generic (
        IMAGE_SIZE : integer := 28;
        KERNEL_SIZE : integer := 3;
        NUM_FILTERS : integer := 8;
        STRIDE : integer := 1
    );
    Port ( 
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        enable : in STD_LOGIC;
        input_data : in PIXEL;
        output_data : out OUTPUT_ARRAY(0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                       0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                       0 to 1);
        done : out STD_LOGIC
    );
end conv_layer;

architecture Behavioral of conv_layer is
begin
    -- Architecture logic
    process(clk, rst)
    begin 
        if(rst) then
            output_data <= (others => (others => (others => '0')));
        elsif rising_edge(clk) then
            
end Behavioral;

