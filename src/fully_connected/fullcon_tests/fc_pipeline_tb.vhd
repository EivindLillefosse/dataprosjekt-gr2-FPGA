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

    -- Sequencer Signals (between FC1 and FC2)
    signal seq_input_valid  : std_logic;
    signal seq_input_ready  : std_logic;
    signal seq_input_data   : WORD_ARRAY_16(0 to FC1_OUTPUT_NODES-1);
    
    signal seq_output_valid : std_logic;
    signal seq_output_ready : std_logic;
    signal seq_output_data  : WORD_16;
    signal seq_output_index : integer range 0 to FC1_OUTPUT_NODES-1;

    -- FC2 Layer Signals
    signal fc2_input_valid  : std_logic := '0';
    signal fc2_input_ready  : std_logic;
    signal fc2_input_data   : WORD_16;
    signal fc2_input_index  : integer range 0 to FC2_INPUT_NODES-1;
    
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

    -- Instantiate Sequencer (FC1 -> FC2)
    sequencer_inst : entity work.fc_sequencer
        generic map (
            NUM_NEURONS => FC1_OUTPUT_NODES
        )
        port map (
            clk          => clk,
            rst          => rst,
            input_valid  => seq_input_valid,
            input_ready  => seq_input_ready,
            input_data   => seq_input_data,
            output_valid => seq_output_valid,
            output_ready => seq_output_ready,
            output_data  => seq_output_data,
            output_index => seq_output_index
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
    -- Interconnect: FC1 -> Sequencer
    -- =====================================================================
    seq_input_valid <= fc1_output_valid;
    seq_input_data  <= fc1_output_data;
    fc1_output_ready <= seq_input_ready;

    -- =====================================================================
    -- Interconnect: Sequencer -> FC2
    -- =====================================================================
    fc2_input_valid <= seq_output_valid;
    fc2_input_data  <= seq_output_data;
    fc2_input_index <= seq_output_index;
    seq_output_ready <= fc2_input_ready;

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
        
        fc1_input_valid <= '0';

        report "FC1: All 400 inputs sent" severity note;
        wait for CLK_PERIOD;

        -- Phase 3: Wait for FC1 to complete computation
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

        -- Phase 4: Verify sequencer is streaming to FC2
        report "TEST PHASE 4: Verifying sequencer is streaming" severity note;
        if seq_output_valid = '1' then
            report "PASS: Sequencer output is valid" severity note;
        else
            report "ERROR: Sequencer output should be valid" severity error;
        end if;

        wait for CLK_PERIOD;

        -- Phase 5: Wait for sequencer to stream all 64 values to FC2
        -- The sequencer automatically streams, FC2 automatically consumes
        report "TEST PHASE 5: Waiting for sequencer to stream 64 outputs to FC2" severity note;
        wait_cycles := 0;
        while seq_output_valid = '1' and wait_cycles < 1000 loop
            wait for CLK_PERIOD;
            wait_cycles := wait_cycles + 1;
        end loop;

        report "Sequencer finished streaming after cycles:" & integer'image(wait_cycles) severity note;
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
        
        if seq_input_ready = '1' then
            report "PASS: Sequencer is ready for new data" severity note;
        else
            report "ERROR: Sequencer should be ready after streaming complete" severity error;
        end if;

        wait for 500 * CLK_PERIOD;

        -- Phase 8: Simulation complete
        report "TEST COMPLETE: Pipeline integration test finished" severity note;
        
        wait;
    end process;

end tb;
