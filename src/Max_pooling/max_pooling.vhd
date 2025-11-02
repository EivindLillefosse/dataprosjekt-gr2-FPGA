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
        INPUT_SIZE     : integer := 26;   -- Input matrix width (e.g., 8 for 8x8)
        INPUT_CHANNELS : integer := 8;    -- Number of input channels
        BLOCK_SIZE     : integer := 2     -- Pooling block size (2x2)
    );
    port ( 
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        pixel_in_valid  : in  std_logic;                              -- New pixel available
        pixel_in_ready  : out std_logic;                              -- Ready to accept new pixel
        pixel_in        : in  WORD_ARRAY(0 to INPUT_CHANNELS-1);      -- Input pixel
        pixel_in_row    : in integer;                                 -- Input pixel row
        pixel_in_col    : in integer;                                 -- Input pixel column

        pixel_out       : out WORD_ARRAY(0 to INPUT_CHANNELS-1);      -- Output pixel
        pixel_out_ready : out std_logic                               -- Output pixel valid
    );
end max_pooling;

architecture Behavioral of max_pooling is
    
    -- Constants
    constant OUTPUT_SIZE  : integer := INPUT_SIZE / 2;

    -- State machine
    type state_type is (IDLE, RECEIVING, DONE);
    signal state : state_type;

    -- Store largest pixel in 2x2 window
    signal curr_largest : WORD_ARRAY(0 to INPUT_CHANNELS-1) := (others => (others => '0'));

    -- Count input pixels
    signal pixel_count : unsigned(7 downto 0) := (others => '0');

    -- Control signals
    signal running : std_logic := '0';

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= IDLE;
                pixel_count <= (others => '0');
                pixel_out_ready <= '0';
                pixel_in_ready <= '0';
                curr_largest <= (others => (others => '0'));
            else
                case state is
                    when IDLE =>
                        pixel_in_ready <= '1';
                        if pixel_in_valid = '1' and pixel_in_ready = '1' then
                            state <= RECEIVING;
                            pixel_in_ready <= '1';
                            pixel_count <= pixel_count + 1;
                            curr_largest <= pixel_in;
                            pixel_out_ready <= '0';
                        end if;
                    
                    when RECEIVING =>
                        pixel_in_ready <= '0';
                        if pixel_in_valid = '1' then
                            pixel_in_ready <= '1';

                            -- Update largest pixel for each channel
                            for ch in 0 to INPUT_CHANNELS-1 loop
                                if pixel_in(ch) > curr_largest(ch) then
                                    curr_largest(ch) <= pixel_in(ch);
                                end if;
                            end loop;

                            -- Update counters
                            if pixel_count = to_unsigned(BLOCK_SIZE*BLOCK_SIZE - 1, pixel_count'length) then
                                pixel_count <= (others => '0');
                                
                                -- Finished 2x2 block
                                pixel_out_ready <= '1';
                                pixel_in_ready <= '0';
                                state <= DONE;
                            else
                                pixel_count <= pixel_count + 1;
                            end if;
                        end if;
                    when DONE =>
                        pixel_out <= curr_largest;
                        if pixel_out_ready = '1' then
                            state <= IDLE;
                            pixel_out_ready <= '0';
                            pixel_in_ready <= '1';
                        end if;
                end case;
            end if;
        end if;
    end process;

end Behavioral;