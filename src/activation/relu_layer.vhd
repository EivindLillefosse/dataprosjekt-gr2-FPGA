----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: ReLU Activation Layer
-- Module Name: relu_layer - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular ReLU activation function
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity relu_layer is
    generic (
        NUM_FILTERS : integer := 8;
        DATA_WIDTH  : integer := 16
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        data_in     : in  WORD_ARRAY_16(0 to NUM_FILTERS-1);
        data_valid  : in  std_logic;
        data_out    : out WORD_ARRAY_16(0 to NUM_FILTERS-1);
        valid_out   : out std_logic
    );
end relu_layer;

architecture Behavioral of relu_layer is

begin

    relu_proc: process(clk, rst)
    begin
        if rst = '1' then
            data_out <= (others => (others => '0'));
            valid_out <= '0';
            
        elsif rising_edge(clk) then
            if data_valid = '1' then
                -- Apply ReLU activation (max(0, x))
                for i in 0 to NUM_FILTERS-1 loop
                    if data_in(i)(DATA_WIDTH-1) = '0' then  -- Check MSB for positive
                        data_out(i) <= data_in(i);
                    else
                        data_out(i) <= (others => '0');  -- Zero for negative
                    end if;
                end loop;
                valid_out <= '1';
            else
                valid_out <= '0';
            end if;
        end if;
    end process;

end Behavioral;