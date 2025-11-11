----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.05.2025
-- Design Name: FC Pipeline Integration Test
-- Module Name: fc_pipeline_tb
-- Project Name: CNN Accelerator
-- Description: Comprehensive integration testbench for FC1 to Buffer to FC2 pipeline
--              Tests complete data flow with handshake protocol
--              Simulates realistic data transfer between fully connected layers
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fc_pipeline_tb is
end fc_pipeline_tb;

architecture tb of fc_pipeline_tb is

    constant CLK_PERIOD : time := 10 ns;
    constant FC1_INPUT_NODES : integer := 400;
    constant FC1_OUTPUT_NODES : integer := 64;
    constant FC2_INPUT_NODES : integer := 64;
    constant FC2_OUTPUT_NODES : integer := 10;

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';

    -- FC1 Layer Signals
    signal fc1_input_valid  : std_logic := '0';
    signal fc1_input_ready  : std_logic;
    signal fc1_input_data   : WORD_16;
    signal fc1_input_index  : integer range 0 to FC1_INPUT_NODES-1 := 0;
    
    signal fc1_output_valid : std_logic;
    signal fc1_output_ready : std_logic;
    signal fc1_output_data  : WORD_ARRAY_16(0 to FC1_OUTPUT_NODES-1);

    -- Buffer Signals
    signal buf_input_valid  : std_logic;
    signal buf_input_ready  : std_logic;
    signal buf_input_data   : WORD_ARRAY_16(0 to FC1_OUTPUT_NODES-1);
    
    signal buf_output_valid : std_logic;
    signal buf_output_ready : std_logic;
    signal buf_output_data  : WORD_ARRAY_16(0 to FC1_OUTPUT_NODES-1);

    -- FC2 Layer Signals
    signal fc2_input_valid  : std_logic := '0';
    signal fc2_input_ready  : std_logic;
    signal fc2_input_data   : WORD_16;
    signal fc2_input_index  : integer range 0 to FC2_INPUT_NODES-1 := 0;
    
    signal fc2_output_valid : std_logic;
    signal fc2_output_ready : std_logic := '1';
    signal fc2_output_data  : WORD_ARRAY_16(0 to FC2_OUTPUT_NODES-1);

begin

    -- Instantiate FC1 Layer
    fc1_inst : entity work.fullyconnected
        generic map (
            NODES_IN  => FC1_INPUT_NODES,
            NODES_OUT => FC1_OUTPUT_NODES,
            LAYER_ID  => 0
        )
        port map (
            clk             => clk,
            rst             => rst,
            pixel_in_valid  => fc1_input_valid,
            pixel_in_ready  => fc1_input_ready,
            pixel_in_data   => fc1_input_data,
            pixel_in_index  => fc1_input_index,
            pixel_out_valid => fc1_output_valid,
            pixel_out_ready => fc1_output_ready,
            pixel_out_data  => fc1_output_data
        );

    -- Instantiate Buffer
    buffer_inst : entity work.fc_layer_buffer
        generic map (
            DATA_WIDTH  => 8,
            NUM_NEURONS => FC1_OUTPUT_NODES
        )
        port map (
            clk           => clk,
            rst           => rst,
            input_valid   => buf_input_valid,
            input_data    => buf_input_data,
            input_ready   => buf_input_ready,
            output_valid  => buf_output_valid,
            output_data   => buf_output_data,
            output_ready  => buf_output_ready
        );

    -- Instantiate FC2 Layer
    fc2_inst : entity work.fullyconnected
        generic map (
            NODES_IN  => FC2_INPUT_NODES,
            NODES_OUT => FC2_OUTPUT_NODES,
            LAYER_ID  => 1
        )
        port map (
            clk             => clk,
            rst             => rst,
            pixel_in_valid  => fc2_input_valid,
            pixel_in_ready  => fc2_input_ready,
            pixel_in_data   => fc2_input_data,
            pixel_in_index  => fc2_input_index,
            pixel_out_valid => fc2_output_valid,
            pixel_out_ready => fc2_output_ready,
            pixel_out_data  => fc2_output_data
        );

    -- =====================================================================
    -- Interconnect: FC1 -> Buffer
    -- =====================================================================
    buf_input_valid <= fc1_output_valid;
    buf_input_data  <= fc1_output_data;
    -- FC1 output ready is driven by buffer input ready
    -- This tells FC1 when buffer can accept data
    fc1_output_ready <= buf_input_ready;

    -- =====================================================================
    -- Interconnect: Buffer -> FC2
    -- =====================================================================
    -- Buffer output data flows to FC2
    buf_output_ready <= fc2_input_ready;
    fc2_input_valid  <= buf_output_valid;
    
    -- Multiplex buffer output by index for FC2 sequential input
    fc2_input_data <= buf_output_data(fc2_input_index) when buf_output_valid = '1' else (others => '0');

    -- Clock generation
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Test stimulus process
    process
        variable input_count : integer;
        variable wait_cycles : integer;
    begin
        -- Phase 1: Reset
        report "TEST PHASE 1: Reset" severity note;
        rst <= '1';
        fc1_input_valid <= '0';
        fc2_input_index <= 0;
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Phase 2: Send data to FC1 (400 input pixels)
        report "TEST PHASE 2: Sending 400 inputs to FC1" severity note;
        input_count := 0;
        
        while input_count < FC1_INPUT_NODES loop
            if fc1_input_ready = '1' then
                fc1_input_valid <= '1';
                fc1_input_index <= input_count;
                fc1_input_data <= std_logic_vector(to_unsigned(input_count mod 256, 16));
                
                wait for CLK_PERIOD;
                fc1_input_valid <= '0';
                input_count := input_count + 1;
                
                wait for CLK_PERIOD;
            else
                wait for CLK_PERIOD;
            end if;
        end loop;

        report "FC1: All 400 inputs sent" severity note;
        wait for CLK_PERIOD;

        -- Phase 3: Wait for FC1 to complete computation and fill buffer
        report "TEST PHASE 3: Waiting for FC1 to complete" severity note;
        wait_cycles := 0;
        while fc1_output_valid = '0' and wait_cycles < 2000 loop
            wait for CLK_PERIOD;
            wait_cycles := wait_cycles + 1;
        end loop;

        if fc1_output_valid = '1' then
            report "FC1 completed output valid after cycles:" & integer'image(wait_cycles) severity note;
        else
            report "ERROR: FC1 did not complete within timeout" severity error;
        end if;

        wait for CLK_PERIOD;

        -- Phase 4: Verify buffer received FC1 data
        report "TEST PHASE 4: Verifying buffer state" severity note;
        if buf_output_valid = '1' then
            report "PASS: Buffer output is valid" severity note;
        else
            report "ERROR: Buffer output should be valid" severity error;
        end if;

        wait for CLK_PERIOD;

        -- Phase 5: Feed buffered data to FC2 (64 inputs)
        -- Note: fc2_input_valid is driven by the concurrent interconnect (buf_output_valid)
        -- so the procedural testbench must not drive fc2_input_valid (avoids multiple drivers).
        report "TEST PHASE 5: Sending 64 buffered outputs to FC2" severity note;
        input_count := 0;

        while input_count < FC2_INPUT_NODES loop
            -- Wait until buffer has valid data and FC2 is ready to accept it
            if buf_output_valid = '1' and fc2_input_ready = '1' then
                -- Set the index for FC2 to read the correct element from buffer
                fc2_input_index <= input_count;
                -- Advance one clock so FC2 samples the data/index
                wait until rising_edge(clk);
                input_count := input_count + 1;
            else
                wait until rising_edge(clk);
            end if;
        end loop;

        report "FC2: All 64 inputs sent" severity note;
        wait for CLK_PERIOD;

        -- Phase 6: Wait for FC2 to complete
        report "TEST PHASE 6: Waiting for FC2 to complete" severity note;
        wait_cycles := 0;
        while fc2_output_valid = '0' and wait_cycles < 3000 loop
            wait for CLK_PERIOD;
            wait_cycles := wait_cycles + 1;
        end loop;

        if fc2_output_valid = '1' then
            report "FC2 completed output valid after cycles:" & integer'image(wait_cycles) severity note;
        else
            report "ERROR: FC2 did not complete within timeout" severity error;
        end if;

        wait for CLK_PERIOD;

        -- Phase 7: Verify pipeline reset
        report "TEST PHASE 7: Verify pipeline can accept new data" severity note;
        
        if buf_input_ready = '1' then
            report "PASS: Buffer is ready for new data" severity note;
        else
            report "ERROR: Buffer should be ready after FC2 consumed data" severity error;
        end if;

        wait for 500 * CLK_PERIOD;

        -- Phase 8: Simulation complete
        report "TEST COMPLETE: Pipeline integration test finished" severity note;
        
        wait;
    end process;

end tb;
