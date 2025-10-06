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

entity max_pooling is
    generic (
        INPUT_WIDTH  : integer := 26;   -- Input matrix width (e.g., 8 for 8x8)
        INPUT_HEIGHT : integer := 26;   -- Input matrix height
        PIXEL_WIDTH  : integer := 16   -- 16-bit pixels
    );
    port ( 
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        start       : in  std_logic;   -- Start new frame
        pixel_valid : in  std_logic;   -- New pixel available
        pixel_in    : in  std_logic_vector(PIXEL_WIDTH-1 downto 0);  -- Input pixel
        
        pixel_out   : out std_logic_vector(PIXEL_WIDTH-1 downto 0);  -- Output pixel
        pixel_ready : out std_logic;   -- Output pixel valid
        frame_done  : out std_logic    -- Complete frame processed
    );
end max_pooling;

architecture Behavioral of max_pooling is
    
    -- Constants
    constant OUTPUT_WIDTH  : integer := INPUT_WIDTH / 2;
    constant OUTPUT_HEIGHT : integer := INPUT_HEIGHT / 2;
    
    -- State machine
    type state_type is (IDLE, RECEIVING, PROCESSING);
    signal state : state_type;
    
    -- Position counters - use fixed-size unsigned for better synthesis
    signal row_count    : unsigned(7 downto 0);  -- Supports up to 256
    signal col_count    : unsigned(7 downto 0);  -- Supports up to 256
    signal output_row   : unsigned(6 downto 0);  -- Supports up to 128
    signal output_col   : unsigned(6 downto 0);  -- Supports up to 128
    
    -- Line buffer to store one complete row
    type line_buffer_type is array (0 to INPUT_WIDTH-1) of std_logic_vector(PIXEL_WIDTH-1 downto 0);
    signal line_buffer : line_buffer_type;
    
    -- Current and previous pixels for window formation
    signal prev_pixel : std_logic_vector(PIXEL_WIDTH-1 downto 0);
    signal curr_pixel : std_logic_vector(PIXEL_WIDTH-1 downto 0);
    
    -- 2x2 window storage (when ready)
    signal window_00 : std_logic_vector(PIXEL_WIDTH-1 downto 0); -- Top-left
    signal window_01 : std_logic_vector(PIXEL_WIDTH-1 downto 0); -- Top-right  
    signal window_10 : std_logic_vector(PIXEL_WIDTH-1 downto 0); -- Bottom-left
    signal window_11 : std_logic_vector(PIXEL_WIDTH-1 downto 0); -- Bottom-right
    
    -- Control signals
    signal pixel_ready_reg : std_logic;
    signal frame_done_reg : std_logic;
    signal pixel_out_reg : std_logic_vector(PIXEL_WIDTH-1 downto 0);

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= IDLE;
                row_count <= (others => '0');
                col_count <= (others => '0');
                output_row <= (others => '0');
                output_col <= (others => '0');
                pixel_ready_reg <= '0';
                frame_done_reg <= '0';
                pixel_out_reg <= (others => '0');
                
                -- Clear line buffer
                for i in 0 to INPUT_WIDTH-1 loop
                    line_buffer(i) <= (others => '0');
                end loop;
                
            else
                -- Default values
                pixel_ready_reg <= '0';
                frame_done_reg <= '0';
                
                case state is
                    when IDLE =>
                        if start = '1' then
                            state <= RECEIVING;
                            row_count <= (others => '0');
                            col_count <= (others => '0');
                            output_row <= (others => '0');
                            output_col <= (others => '0');
                        end if;
                    
                    when RECEIVING =>
                        if pixel_valid = '1' then
                            curr_pixel <= pixel_in;
                            
                            -- Update line buffer with current row
                            line_buffer(to_integer(col_count)) <= pixel_in;
                            
                            -- Check if we can form a 2x2 window (need to be at odd row and odd col)
                            if row_count > 0 and col_count > 0 and 
                               row_count(0) = '1' and col_count(0) = '1' then
                                
                                -- Form 2x2 window from:
                                -- Top row (previous): stored in line buffer from previous row processing
                                -- Bottom row (current): previous pixel and current pixel
                                
                                -- This is a simplified approach - proper implementation needs
                                -- more sophisticated buffering for arbitrary input sizes
                                window_00 <= prev_pixel;     -- Top-left (from previous position)
                                window_01 <= curr_pixel;     -- Top-right (current input)  
                                window_10 <= prev_pixel;     -- Bottom-left (previous in current row)
                                window_11 <= pixel_in;       -- Bottom-right (current pixel)
                                
                                state <= PROCESSING;
                            end if;
                            
                            -- Store previous pixel for next iteration
                            prev_pixel <= pixel_in;
                            
                            -- Update position counters
                            if col_count = to_unsigned(INPUT_WIDTH-1, 8) then
                                col_count <= (others => '0');
                                if row_count = to_unsigned(INPUT_HEIGHT-1, 8) then
                                    frame_done_reg <= '1';
                                    state <= IDLE;
                                else
                                    row_count <= row_count + 1;
                                end if;
                            else
                                col_count <= col_count + 1;
                            end if;
                        end if;
                    
                    when PROCESSING =>
                        -- Find maximum using tree structure for better timing
                        -- Stage 1: Compare pairs
                        if unsigned(window_00) >= unsigned(window_01) then
                            if unsigned(window_10) >= unsigned(window_11) then
                                -- Stage 2: Compare winners
                                if unsigned(window_00) >= unsigned(window_10) then
                                    pixel_out_reg <= window_00;
                                else
                                    pixel_out_reg <= window_10;
                                end if;
                            else
                                if unsigned(window_00) >= unsigned(window_11) then
                                    pixel_out_reg <= window_00;
                                else
                                    pixel_out_reg <= window_11;
                                end if;
                            end if;
                        else
                            if unsigned(window_10) >= unsigned(window_11) then
                                if unsigned(window_01) >= unsigned(window_10) then
                                    pixel_out_reg <= window_01;
                                else
                                    pixel_out_reg <= window_10;
                                end if;
                            else
                                if unsigned(window_01) >= unsigned(window_11) then
                                    pixel_out_reg <= window_01;
                                else
                                    pixel_out_reg <= window_11;
                                end if;
                            end if;
                        end if;
                        
                        pixel_ready_reg <= '1';
                        state <= RECEIVING;
                        
                        -- Update output position
                        if output_col = to_unsigned(OUTPUT_WIDTH-1, 7) then
                            output_col <= (others => '0');
                            if output_row = to_unsigned(OUTPUT_HEIGHT-1, 7) then
                                output_row <= (others => '0');
                            else
                                output_row <= output_row + 1;
                            end if;
                        else
                            output_col <= output_col + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    -- Output assignments
    pixel_out <= pixel_out_reg;
    pixel_ready <= pixel_ready_reg;
    frame_done <= frame_done_reg;

end Behavioral;