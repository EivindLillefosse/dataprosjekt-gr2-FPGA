----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Martin Nilsen
-- 
-- Create Date: 19.09.2025 13:20:31
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
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;



entity max_pooling is
    generic (
        CONV_SIZE : integer := 26;
        POOL_SIZE : integer := 2;
        NUM_FILTERS : integer := 8
        
    );
    Port ( 
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        enable : in STD_LOGIC;
        input_data : in OUTPUT_ARRAY(0 to NUM_FILTERS-1, 
                                       0 to CONV_SIZE-1, 
                                       0 to CONV_SIZE-1);
        output_data : out OUTPUT_ARRAY(0 to NUM_FILTERS-1, 
                                       0 to (CONV_SIZE/POOL_SIZE)-1,
                                        0 to (CONV_SIZE/POOL_SIZE)-1);
        done : out STD_LOGIC
    );
end max_pooling;

architecture Behavioral of max_pooling is
    constant OUT_SIZE : integer := CONV_SIZE / POOL_SIZE;
    subtype pixel_t is std_logic_vector(7 downto 0); -- Change if needed
begin
    process(clk)
        variable max_val : unsigned(7 downto 0);
        variable curr_val : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                for f in 0 to NUM_FILTERS-1 loop
                    for i in 0 to OUT_SIZE-1 loop
                        for j in 0 to OUT_SIZE-1 loop
                            output_data(f, i, j) <= (others => '0');
                        end loop;
                    end loop;
                end loop;
                done <= '0';
            elsif enable = '1' then
                for f in 0 to NUM_FILTERS-1 loop
                    for i in 0 to OUT_SIZE-1 loop
                        for j in 0 to OUT_SIZE-1 loop
                            -- Initialize max_val with the first value in the 2x2 window
                            max_val := unsigned(input_data(f, i*POOL_SIZE, j*POOL_SIZE));
                            
                            -- Compare with all values in the 2x2 window
                            for di in 0 to POOL_SIZE-1 loop
                                for dj in 0 to POOL_SIZE-1 loop
                                    curr_val := unsigned(input_data(f, i*POOL_SIZE+di, j*POOL_SIZE+dj));
                                    if curr_val > max_val then
                                        max_val := curr_val;
                                    end if;
                                end loop;
                            end loop;
                            
                            -- Assign the maximum value to the output
                            output_data(f, i, j) <= std_logic_vector(max_val);
                        end loop;
                    end loop;
                end loop;
                done <= '1';
            else
                done <= '0';
            end if;
        end if;
    end process;
end Behavioral;