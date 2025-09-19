----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: 
-- Module Name: top - Behavioral
-- Project Name: 
-- Target Devices: 
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


entity reLU is
    generic (
        IMAGE_SIZE : integer := 28;
        KERNEL_SIZE : integer := 3;
        STRIDE : integer := 1
    );
    Port ( 
        enable : in STD_LOGIC;
        done : out STD_LOGIC;
        clk : in STD_LOGIC;
        data : inout OUTPUT_ARRAY(0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                        0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1)
    );
end reLU;

architecture Behavioral of reLU is

begin
    process(clk)
    begin
        if rising_edge(clk) then
            if enable = '1' then
                done <= '0';
                for row in 0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1 loop
                    for col in 0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1 loop
                        if data(row, col)(WORD_SIZE-1) = '1' then -- Check MSB for negative (assuming 8-bit data)
                            data(row, col) <= (others => '0'); 
                        end if;
                    end loop;
                end loop;
                done <= '1';
            else
                done <= '0';
            end if;
        end if;
    end process;

end Behavioral;
