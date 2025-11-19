----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse, Martin Brekke Nilsen, Nikolai Sandvik Nore
-- 
-- Create Date: 11.11.2025
-- Design Name: FC Layer Sequencer
-- Module Name: fc_sequencer
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: 
--   Converts parallel FC layer output (all neurons at once) into sequential
--   stream suitable for next FC layer input (one neuron per clock cycle).
--   Buffers the parallel input when valid, then streams out with handshake.
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fc_sequencer is
    generic (
        NUM_NEURONS : integer := 64  -- Number of neurons to sequence
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Parallel input (all neurons at once)
        input_valid  : in  std_logic;
        input_ready  : out std_logic;
        input_data   : in  WORD_ARRAY_16(0 to NUM_NEURONS-1);
        
        -- Sequential output (one neuron per cycle)
        output_valid : out std_logic;
        output_ready : in  std_logic;
        output_data  : out WORD_16;
        output_index : out integer range 0 to NUM_NEURONS-1
    );
end fc_sequencer;

architecture RTL of fc_sequencer is
    -- Internal buffer to hold captured input
    signal buffered_data : WORD_ARRAY_16(0 to NUM_NEURONS-1);
    
    -- State: are we currently streaming?
    signal streaming     : std_logic := '0';
    
    -- Current output index
    signal curr_index    : integer range 0 to NUM_NEURONS-1 := 0;
    
begin
    -- Drive outputs
    output_data  <= buffered_data(curr_index);
    output_index <= curr_index;
    input_ready  <= not streaming;  -- Ready to accept input when not streaming
    
    -- Sequencing process
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                curr_index    <= 0;
                output_valid  <= '0';
                streaming     <= '0';
                buffered_data <= (others => (others => '0'));
                
            elsif input_valid = '1' and streaming = '0' then
                -- Capture parallel input and start streaming
                buffered_data <= input_data;
                streaming     <= '1';
                output_valid  <= '1';
                curr_index    <= 0;
                
            elsif streaming = '1' and output_ready = '1' then
                -- Consumer accepted current neuron, advance to next
                if curr_index < NUM_NEURONS - 1 then
                    -- More neurons to send
                    curr_index    <= curr_index + 1;
                    output_valid  <= '1';  -- Keep valid high
                else
                    -- Last neuron was just accepted, done streaming
                    curr_index    <= 0;
                    output_valid  <= '0';
                    streaming     <= '0';
                end if;
            end if;
        end if;
    end process;

end RTL;
