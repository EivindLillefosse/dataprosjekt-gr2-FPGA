----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.05.2025
-- Design Name: FC Layer Buffer
-- Module Name: fc_layer_buffer - RTL
-- Project Name: CNN Accelerator
-- Description: Register buffer between FC1 and FC2 layers
--              Stores 64x8-bit output from FC1 (512 bits total)
--              Ensures FC2 doesn't read until FC1 has completed
--              Implements handshake protocol for data flow control
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fc_layer_buffer is
    generic (
        DATA_WIDTH   : integer := 8;   -- Each neuron output is 8 bits
        NUM_NEURONS  : integer := 64   -- Buffer 64 neuron outputs
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        
        -- Input side (from FC1)
        input_valid   : in  std_logic;  -- FC1 output is valid
        input_data    : in  WORD_ARRAY_16(0 to NUM_NEURONS-1);  -- 64x 8-bit neurons
        input_ready   : out std_logic;  -- Buffer ready to accept
        
        -- Output side (to FC2)
        output_valid  : out std_logic;  -- Buffered data is valid
        output_data   : out WORD_ARRAY_16(0 to NUM_NEURONS-1);  -- 64x 8-bit neurons
        output_ready  : in  std_logic   -- FC2 is ready to accept
    );
end fc_layer_buffer;

architecture RTL of fc_layer_buffer is

    type state_type is (EMPTY, FULL, DRAINING);
    signal state      : state_type := EMPTY;
    signal next_state : state_type;
    
    -- Storage register for buffered data (512 bits total)
    signal buffer_data : WORD_ARRAY_16(0 to NUM_NEURONS-1) := (others => (others => '0'));
    
    -- Next-value signals for outputs (combinational)
    signal v_input_ready : std_logic;
    signal v_output_valid : std_logic;
    signal v_output_data : WORD_ARRAY_16(0 to NUM_NEURONS-1);

begin

    -- Combinational next-state logic
    process(state, input_valid, output_ready)
    begin
        next_state <= state;
        
        case state is
            when EMPTY =>
                if input_valid = '1' then
                    next_state <= FULL;
                end if;
            
            when FULL =>
                if output_ready = '1' then
                    next_state <= DRAINING;
                end if;
            
            when DRAINING =>
                -- Wait for output_ready to be deasserted before returning to EMPTY
                if output_ready = '0' then
                    next_state <= EMPTY;
                end if;
            
            when others =>
                next_state <= EMPTY;
        end case;
    end process;

    -- Combinational output logic
    process(state, buffer_data)
    begin
        case state is
            when EMPTY =>
                v_input_ready <= '1';
                v_output_valid <= '0';
                v_output_data <= (others => (others => '0'));
            
            when FULL =>
                v_input_ready <= '0';
                v_output_valid <= '1';
                v_output_data <= buffer_data;
            
            when DRAINING =>
                v_input_ready <= '0';
                v_output_valid <= '1';
                v_output_data <= buffer_data;
            
            when others =>
                v_input_ready <= '1';
                v_output_valid <= '0';
                v_output_data <= (others => (others => '0'));
        end case;
    end process;

    -- Synchronous state and buffer register
    process(clk, rst)
    begin
        if rst = '1' then
            state <= EMPTY;
            buffer_data <= (others => (others => '0'));
            input_ready <= '1';
            output_valid <= '0';
            output_data <= (others => (others => '0'));
        elsif rising_edge(clk) then
            state <= next_state;
            input_ready <= v_input_ready;
            output_valid <= v_output_valid;
            output_data <= v_output_data;
            
            -- Capture input data when transitioning to FULL
            if state = EMPTY and input_valid = '1' then
                buffer_data <= input_data;
            end if;
        end if;
    end process;

end RTL;
