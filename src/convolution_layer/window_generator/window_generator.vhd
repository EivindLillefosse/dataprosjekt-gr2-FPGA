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


entity window_gen is
    Port ( 
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        enable : in STD_LOGIC;
        input_data : in PIXEL;
        output_data : out IMAGE_VECTOR;
        done : out STD_LOGIC
    );
end window_gen;

architecture Behavioral of window_gen is

begin
    process(clk, rst)
        variable column_ptr : integer := 0;
        variable row_ptr : integer := 0;
        variable window : IMAGE_VECTOR := (others => (others => (others => '0')));
    begin
        if rst = '1' then
            output_data <= (others => (others => (others => '0')));
            done <= '0';
        elsif rising_edge(clk) then
            if enable = '1' then
                -- Add new pixel to window
                if (row_ptr < KERNEL_SIZE) then
                    window(row_ptr, column_ptr) := input_data;
                    
                    -- Update pointers
                    if (column_ptr = KERNEL_SIZE - 1) then
                        column_ptr := 0;
                        if (row_ptr = KERNEL_SIZE - 1) then
                            -- Window is full, output it
                            output_data <= window;
                            done <= '1';
                            -- Clear window, and reset pointers
                            window := (others => (others => (others => '0')));
                            row_ptr := 0;
                            column_ptr := 0;
                        else
                            row_ptr := row_ptr + 1;
                            done <= '0';
                        end if;
                    else
                        column_ptr := column_ptr + 1;
                        done <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;


end Behavioral;
