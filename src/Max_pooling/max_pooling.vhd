----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Martin Nilsen, Eivind Lillefosse
-- 
-- Create Date: 19.09.2025 13:20:31
-- Design Name: Multiplier
-- Module Name: top - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: Max Pooling module for CNN Accelerator, implements NxN max pooling over input feature maps
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
        INPUT_SIZE     : integer := 26;   -- Input matrix width (e.g., 8 for 8x8)
        INPUT_CHANNELS : integer := 8;    -- Number of input channels
        BLOCK_SIZE     : integer := 2     -- Pooling block size (2x2)
    );
    port ( 
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- Request FROM downstream (what output position is needed)
        pixel_out_req_row   : in  integer;                             -- Requested output row
        pixel_out_req_col   : in  integer;                             -- Requested output col
        pixel_out_req_valid : in  std_logic;                           -- Output position request valid
        pixel_out_req_ready : out std_logic;                           -- Ready to accept output request

        -- Request TO upstream (what input positions we need)
        pixel_in_req_row    : out integer;                             -- Requesting input row
        pixel_in_req_col    : out integer;                             -- Requesting input col
        pixel_in_req_valid  : out std_logic;                           -- Input position request valid
        pixel_in_req_ready  : in  std_logic;                           -- Upstream ready for request

        -- Data FROM upstream (input pixels)
        pixel_in            : in  WORD_ARRAY_16(0 to INPUT_CHANNELS-1);   -- Input pixel data
        pixel_in_valid      : in  std_logic;                           -- Input data valid
        pixel_in_ready      : out std_logic;                           -- Ready to accept input data

        -- Data TO downstream (output result)
        pixel_out           : out WORD_ARRAY_16(0 to INPUT_CHANNELS-1);  -- Output pixel data
        pixel_out_valid     : out std_logic;                           -- Output data valid
        pixel_out_ready     : in  std_logic                            -- Downstream ready for data
    );
end max_pooling;

architecture Behavioral of max_pooling is
    
    -- Constants
    constant OUTPUT_SIZE  : integer := INPUT_SIZE / 2;

    -- State machine
    type state_type is (IDLE, REQUEST_INPUT, WAIT_INPUT, RECEIVING, OUTPUT_READY);
    signal state : state_type := IDLE;

    -- Store largest pixel in 2x2 window (16-bit Q9.6 format)
    signal curr_largest : WORD_ARRAY_16(0 to INPUT_CHANNELS-1) := (others => x"8000");  -- Initialize to most negative 16-bit value

    -- Count input pixels in current 2x2 block
    signal pixel_count : integer range 0 to BLOCK_SIZE*BLOCK_SIZE-1 := 0;

    -- Store the requested output position
    signal req_out_row : integer := 0;
    signal req_out_col : integer := 0;

    -- Registered request positions (to avoid enable-by-reset warnings)
    signal req_in_row_reg : integer := 0;
    signal req_in_col_reg : integer := 0;

begin

    -- Combinational output assignments (eliminates RESET-3 warnings)
    pixel_out <= curr_largest;
    pixel_in_req_row <= req_in_row_reg;
    pixel_in_req_col <= req_in_col_reg;

    -- Main FSM
    process(clk)
        variable next_req_row : integer;
        variable next_req_col : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state                <= IDLE;
                pixel_count          <= 0;
                pixel_out_valid      <= '0';
                pixel_out_req_ready  <= '0';
                pixel_in_req_valid   <= '0';
                pixel_in_ready       <= '0';
                curr_largest         <= (others => x"8000");  -- Reset to most negative Q1.6 value
                req_out_row          <= 0;
                req_out_col          <= 0;
                req_in_row_reg       <= 0;
                req_in_col_reg       <= 0;
                
            else
                -- Default values
                pixel_out_req_ready  <= '0';
                pixel_in_req_valid   <= '0';
                pixel_in_ready       <= '0';
                pixel_out_valid      <= '0';
                
                case state is
                    when IDLE =>
                        -- Wait for downstream to request an output position
                        if pixel_out_req_valid = '1' then
                            pixel_out_req_ready <= '1';  -- Acknowledge request
                            req_out_row <= pixel_out_req_row;
                            req_out_col <= pixel_out_req_col;
                            pixel_count <= 0;
                            curr_largest <= (others => x"8000");  -- Reset to most negative Q1.6 value
                            state <= REQUEST_INPUT;
                        end if;
                    
                    when REQUEST_INPUT =>
                        -- Calculate which input position we need based on pixel_count
                        next_req_row := (pixel_count / BLOCK_SIZE) + (req_out_row * BLOCK_SIZE);
                        next_req_col := (pixel_count mod BLOCK_SIZE) + (req_out_col * BLOCK_SIZE);
                        
                        req_in_row_reg <= next_req_row;
                        req_in_col_reg <= next_req_col;
                        pixel_in_req_valid <= '1';  -- Request this input position
                        
                        if pixel_in_req_ready = '1' then
                            -- Upstream acknowledged our request
                            state <= WAIT_INPUT;
                        end if;
                    
                    when WAIT_INPUT =>
                        -- Wait for upstream to provide the data
                        if pixel_in_valid = '1' then
                            pixel_in_ready <= '1';  -- Acknowledge data receipt
                            
                            -- Update max for each channel
                            for ch in 0 to INPUT_CHANNELS-1 loop
                                if signed(pixel_in(ch)) > signed(curr_largest(ch)) then
                                    curr_largest(ch) <= pixel_in(ch);
                                end if;
                            end loop;
                            
                            state <= RECEIVING;
                        end if;
                    
                    when RECEIVING =>
                        -- Check if we've received all pixels in the 2x2 block
                        if pixel_count = BLOCK_SIZE*BLOCK_SIZE - 1 then
                            -- All pixels received, output is read
                            pixel_out_valid <= '1';
                            state <= OUTPUT_READY;
                        else
                            -- Need more pixels
                            pixel_count <= pixel_count + 1;
                            state <= REQUEST_INPUT;
                        end if;
                    
                    when OUTPUT_READY =>
                        -- Provide output to downstream
                        
                        if pixel_out_ready = '1' then
                            -- Downstream accepted the data
                            state <= IDLE;
                        end if;
                        
                end case;
            end if;
        end if;
    end process;

end Behavioral;