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

entity conv_layer is
    generic (
        DATA_WIDTH : integer := 8;
        IMAGE_SIZE : integer := 28;
        KERNEL_SIZE : integer := 3;
        NUM_FILTERS : integer := 8
    );
    Port ( 
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        enable : in STD_LOGIC;
        input_data : in STD_LOGIC_VECTOR(DATA_WIDTH downto 0);
        output_data : out STD_LOGIC_VECTOR(DATA_WIDTH downto 0);
        done : out STD_LOGIC
    );
end conv_layer;

architecture Behavioral of conv_layer is

begin


end Behavioral;

