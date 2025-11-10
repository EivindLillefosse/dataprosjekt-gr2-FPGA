----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.04.2025
-- Design Name: Fully Connected Layer
-- Module Name: Calc Index
-- Project Name: CNN Accelerator
-- Description:  Calculate flattened index from 3D tensor indices
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;
use work.bias_pkg.all;

entity calc_index is
    generic (
        NODES_IN       : integer := 400;
        INPUT_CHANNELS : integer := 16;
        INPUT_SIZE     : integer := 5
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        enable  : in  std_logic;  -- Start requesting pixels
        
        -- Request to upstream (max pooling layer) - only row/col needed
        req_row     : out integer range 0 to INPUT_SIZE-1;
        req_col     : out integer range 0 to INPUT_SIZE-1;
        req_valid   : out std_logic;
        
        -- Input from max pooling: all 16 channels at once (16x8 bits)
        pool_pixel_data  : in WORD_ARRAY(0 to INPUT_CHANNELS-1);
        pool_pixel_valid : in std_logic;
        pool_pixel_ready : out std_logic;
        
        -- Output to FC layer: selected single channel pixel
        fc_pixel_out    : out WORD;
        fc_pixel_valid  : out std_logic;
        
        -- Current index being requested (for debugging/monitoring)
        curr_index  : out integer range 0 to NODES_IN-1;
        
        -- Done signal when all 400 pixels requested
        done        : out std_logic
    );
end calc_index;

architecture Structural of calc_index is
    signal index_counter : integer range 0 to NODES_IN-1 := 0;
    signal internal_done : std_logic := '0';
    signal current_channel : integer range 0 to INPUT_CHANNELS-1 := 0;
begin
    
    -- Sequential index counter (0 to 399)
    -- Only increment when Pool2 delivers valid data
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Hard reset
                index_counter <= 0;
                internal_done <= '0';
            elsif enable = '1' then
                if internal_done = '1' then
                    -- Was done, now restart
                    index_counter <= 0;
                    internal_done <= '0';
                -- Only advance when Pool2 delivers valid data
                elsif pool_pixel_valid = '1' then
                    if index_counter = NODES_IN - 1 then
                        -- Reached last index, set done
                        internal_done <= '1';
                    else
                        -- Normal increment
                        index_counter <= index_counter + 1;
                    end if;
                end if;
            elsif enable = '0' then
                -- When disabled, clear done flag
                internal_done <= '0';
            end if;
        end if;
    end process;
    
    -- Reverse calculation: 1D index to 3D coordinates
    -- Given: index = (row * WIDTH + col) * CHANNELS + channel
    -- Solve for row, col, channel:
    --   channel = index mod CHANNELS
    --   temp    = index / CHANNELS  (integer division)
    --   col     = temp mod WIDTH
    --   row     = temp / WIDTH
    --
    -- Example mappings (reverse):
    --   index=0   → channel=0,  temp=0,  col=0, row=0  → [0,0,0]
    --   index=15  → channel=15, temp=0,  col=0, row=0  → [0,0,15]
    --   index=16  → channel=0,  temp=1,  col=1, row=0  → [0,1,0]
    --   index=399 → channel=15, temp=24, col=4, row=4  → [4,4,15]
    
    -- Calculate which channel we need from the 16-channel array
    current_channel <= index_counter mod INPUT_CHANNELS;
    
    -- Request position (only row/col, max pooling sends all channels)
    req_col     <= (index_counter / INPUT_CHANNELS) mod INPUT_SIZE;
    req_row     <= index_counter / (INPUT_CHANNELS * INPUT_SIZE);
    req_valid   <= enable and not internal_done;
    
    -- Select the correct channel from pool_pixel_data and forward to FC
    -- Only output when Pool2 delivers valid data
    fc_pixel_out   <= pool_pixel_data(current_channel);
    fc_pixel_valid <= pool_pixel_valid and enable and not internal_done;
    
    -- Assert ready whenever we're enabled and requesting
    pool_pixel_ready <= enable and not internal_done;
    
    -- Status outputs
    curr_index  <= index_counter;
    done        <= internal_done;

end architecture Structural;