----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Convolution Engine
-- Module Name: convolution_engine - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular convolution computation engine with MAC array
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity calculation is
    generic (
        NODES : integer := 64;
        MAC_DATA_WIDTH  : integer := 8;
        MAC_RESULT_WIDTH: integer := 16
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        clear        : in  std_logic;
        -- Input data
        pixel_data   : in  std_logic_vector(MAC_DATA_WIDTH-1 downto 0);
        weight_data  : in  WORD_ARRAY(0 to NODES-1);
        compute_en   : in  std_logic;
        -- Results
        results      : out WORD_ARRAY_16(0 to NODES-1);
        compute_done : out std_logic_vector(NODES-1 downto 0)
    );
end calculation;

architecture Structural of calculation is

begin

    -- Generate MAC instances for each filter
    mac_gen : for i in 0 to NODES-1 generate
        mac_inst : entity work.MAC
            generic map (
                width_a => MAC_DATA_WIDTH,
                width_b => MAC_DATA_WIDTH,
                width_p => MAC_RESULT_WIDTH
            )
            port map (
                clk      => clk,
                rst      => rst,
                pixel_in => pixel_data,
                weights  => weight_data(i),
                valid    => compute_en,
                clear    => clear,
                result   => results(i),
                done     => compute_done(i)
            );
    end generate;

end Structural;