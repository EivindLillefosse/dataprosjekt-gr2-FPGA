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
    constant NUM_POSITIONS : integer := INPUT_SIZE * INPUT_SIZE;  -- 25 spatial positions
    
    signal position_counter : integer range 0 to NUM_POSITIONS-1 := 0;
    signal channel_counter  : integer range 0 to INPUT_CHANNELS-1 := 0;
    signal internal_done    : std_logic := '0';
    signal pool_data_captured : WORD_ARRAY(0 to INPUT_CHANNELS-1) := (others => (others => '0'));
    signal data_valid       : std_logic := '0';
begin
    
    -- Main state machine: request Pool2 position, capture 16 channels, send to FC1 sequentially
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                position_counter <= 0;
                channel_counter <= 0;
                internal_done <= '0';
                data_valid <= '0';
                pool_data_captured <= (others => (others => '0'));
            elsif enable = '1' then
                if internal_done = '1' then
                    -- Restart
                    position_counter <= 0;
                    channel_counter <= 0;
                    internal_done <= '0';
                    data_valid <= '0';
                else
                    -- When Pool2 delivers data, capture it and start sending channels
                    if pool_pixel_valid = '1' and data_valid = '0' then
                        pool_data_captured <= pool_pixel_data;
                        data_valid <= '1';
                        channel_counter <= 0;
                    end if;
                    
                    -- Send captured channels sequentially to FC1
                    if data_valid = '1' then
                        if channel_counter = INPUT_CHANNELS - 1 then
                            -- Sent all 16 channels for this position
                            channel_counter <= 0;
                            data_valid <= '0';
                            
                            if position_counter = NUM_POSITIONS - 1 then
                                -- All positions done
                                internal_done <= '1';
                            else
                                -- Move to next position
                                position_counter <= position_counter + 1;
                            end if;
                        else
                            -- Move to next channel
                            channel_counter <= channel_counter + 1;
                        end if;
                    end if;
                end if;
            elsif enable = '0' then
                internal_done <= '0';
                data_valid <= '0';
            end if;
        end if;
    end process;
    
    -- Reverse calculation: position to 2D coordinates
    -- position = row * INPUT_SIZE + col
    req_row     <= position_counter / INPUT_SIZE;
    req_col     <= position_counter mod INPUT_SIZE;
    req_valid   <= enable and not internal_done and not data_valid;  -- Only request when not processing channels
    
    -- Output current channel from captured data
    fc_pixel_out   <= pool_data_captured(channel_counter);
    fc_pixel_valid <= data_valid and enable and not internal_done;
    
    -- Assert ready when waiting for Pool2 data
    pool_pixel_ready <= enable and not internal_done and not data_valid;
    
    -- Status outputs
    curr_index  <= position_counter * INPUT_CHANNELS + channel_counter;  -- Absolute pixel index (0-399)
    done        <= internal_done;

end architecture Structural;