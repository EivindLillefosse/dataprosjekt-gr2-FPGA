----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Position Calculator
-- Module Name: position_calculator - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular position calculation for convolution processing
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity position_calculator is
    generic (
        IMAGE_SIZE  : integer := 28;
        KERNEL_SIZE : integer := 3;
        BLOCK_SIZE  : integer := 2
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        advance     : in  std_logic;
        -- Current position outputs
        row         : out integer;
        col         : out integer;
        -- Region tracking (within kernel)
        region_row  : out integer range 0 to KERNEL_SIZE-1;
        region_col  : out integer range 0 to KERNEL_SIZE-1;
        region_done : out std_logic;
        layer_done  : out std_logic
    );
end position_calculator;

architecture Behavioral of position_calculator is

    signal current_row : integer := 0;
    signal current_col : integer := 0;
    signal current_region_row : integer range 0 to KERNEL_SIZE-1 := 0;
    signal current_region_col : integer range 0 to KERNEL_SIZE-1 := 0;
    signal position_counter : integer := 0;  -- zero-based index into output positions
    constant OUT_SIZE : integer := IMAGE_SIZE - KERNEL_SIZE + 1;

begin

    -- Output current position
    row <= current_row;
    col <= current_col;
    region_row <= current_region_row;
    region_col <= current_region_col;

    position_proc: process(clk, rst)
        variable block_row, block_col : integer := 0;
        variable within_row, within_col : integer := 0;
        variable block_index : integer := 0;
        variable next_pos_index : integer := 0;
    begin
        if rst = '1' then
            current_row <= 0;
            current_col <= 0;
            current_region_row <= 0;
            current_region_col <= 0;
            position_counter <= 0;  -- start from first position (index 0)
            region_done <= '0';
            layer_done <= '0';
            block_row := 0;
            block_col := 0;
            within_row := 0;
            within_col := 0;
            block_index := 0;
            next_pos_index := 0;

        elsif rising_edge(clk) then
            if advance = '1' then
                -- Normal within-region stepping
                if current_region_col < KERNEL_SIZE - 1 then
                    current_region_col <= current_region_col + 1;
                    -- Check if we just reached the last position
                    if current_region_col + 1 = KERNEL_SIZE - 1 and current_region_row = KERNEL_SIZE - 1 then
                        region_done <= '1';
                    else
                        region_done <= '0';
                    end if;
                    layer_done <= '0';
                elsif current_region_row < KERNEL_SIZE - 1 then
                    -- Move to next row in region
                    current_region_row <= current_region_row + 1;
                    current_region_col <= 0;
                    region_done <= '0';
                    layer_done <= '0';
                else
                    -- We're at the last position in the region (region_row=KERNEL_SIZE-1, region_col=KERNEL_SIZE-1)
                    -- Advance to next output position
                    region_done <= '0';  -- Clear region_done as we move to next position
                    
                    -- Check if this was the last valid output position
                    if position_counter = (OUT_SIZE * OUT_SIZE - 1) then
                        -- Last position - assert layer_done and reset to start
                        layer_done <= '1';
                        position_counter <= 0;
                        current_row <= 0;
                        current_col <= 0;
                        current_region_row <= 0;
                        current_region_col <= 0;
                    else
                        -- Advance to next position index and compute its row/col
                        layer_done <= '0';
                        next_pos_index := position_counter + 1;
                        
                        -- Compute block/within indexes for the next position
                        block_index := next_pos_index / (BLOCK_SIZE * BLOCK_SIZE);
                        within_row := (next_pos_index mod (BLOCK_SIZE * BLOCK_SIZE)) / BLOCK_SIZE;
                        within_col := (next_pos_index mod (BLOCK_SIZE * BLOCK_SIZE)) mod BLOCK_SIZE;
                        block_row := block_index / (OUT_SIZE / BLOCK_SIZE);
                        block_col := block_index mod (OUT_SIZE / BLOCK_SIZE);

                        current_row <= block_row * BLOCK_SIZE + within_row;
                        current_col <= block_col * BLOCK_SIZE + within_col;

                        position_counter <= next_pos_index;
                        -- Reset region indices for the new position
                        current_region_row <= 0;
                        current_region_col <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;