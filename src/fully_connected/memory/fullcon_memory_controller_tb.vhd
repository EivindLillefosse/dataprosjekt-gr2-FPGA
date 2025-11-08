----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.03.2025
-- Design Name: Fully Connected Memory Controller Testbench
-- Module Name: fullcon_memory_controller_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for fully connected weight memory controller
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fullcon_memory_controller_tb is
end fullcon_memory_controller_tb;

architecture Behavioral of fullcon_memory_controller_tb is

    -- Test parameters
    -- Layer 0 (FC1): 400 inputs -> 64 outputs
    -- Layer 1 (FC2): 64 inputs -> 10 outputs
    constant NUM_NODES_0   : integer := 64;
    constant NUM_NODES_1   : integer := 10;
    constant NUM_INPUTS_0  : integer := 400;
    constant NUM_INPUTS_1  : integer := 64;

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    -- Separate pixel_index signals for each UUT to avoid range conflicts
    signal pixel_index_0 : integer range 0 to NUM_INPUTS_0-1 := 0; -- for layer0
    signal pixel_index_1 : integer range 0 to NUM_INPUTS_1-1 := 0; -- for layer1
    signal weight_data   : WORD_ARRAY(0 to NUM_NODES_0-1);
    signal weight_data_1 : WORD_ARRAY(0 to NUM_NODES_1-1);
    
    -- Test control
    signal test_done : boolean := false;
    -- Simulation cycle counter for latency measurement
    signal sim_cycle : integer := 0;

begin

    -- Unit Under Test - Layer 0 (FC1: 400 -> 64)
    uut: entity work.fullcon_memory_controller
        generic map (
            NUM_NODES  => NUM_NODES_0,
            NUM_INPUTS => NUM_INPUTS_0,
            LAYER_ID   => 0
        )
        port map (
            clk => clk,
            pixel_index => pixel_index_0,
            weight_data => weight_data
        );

    -- Second instance to test Layer 1 (FC2: 64 -> 10)
    uut_layer1: entity work.fullcon_memory_controller
        generic map (
            NUM_NODES  => NUM_NODES_1,
            NUM_INPUTS => NUM_INPUTS_1,
            LAYER_ID   => 1
        )
        port map (
            clk => clk,
            pixel_index => pixel_index_1,
            weight_data => weight_data_1
        );

    -- Clock process
    clk_process: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- Simple cycle counter
    cycle_counter: process(clk)
    begin
        if rising_edge(clk) then
            sim_cycle <= sim_cycle + 1;
        end if;
    end process;

    -- Test process
    test_process: process is
        constant MAX_LATENCY : integer := 16;
        type hist_type is array(0 to MAX_LATENCY) of integer;
        variable hist : hist_type := (others => 0);
        variable start_cycle : integer := 0;
        variable latency : integer := 0;
        -- Threshold above which we consider BRAM latency a failure (assumption)
        constant LATENCY_FAIL_THRESHOLD : integer := 4;

        -- Helper: detect unknown/invalid bits in a std_logic_vector
        function has_unknown(slv : std_logic_vector) return boolean is
        begin
            for i in slv'range loop
                if slv(i) = 'U' or slv(i) = 'X' or slv(i) = 'Z' or slv(i) = '-' then
                    return true;
                end if;
            end loop;
            return false;
        end function;

    begin
        -- Initialize
        rst <= '1';
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting fully connected memory controller test...";
        
        -- Test loading weights for different input indices and measure latency
        
        -- Test Layer 0 (FC1): Sample some input indices (not all 400 to save time)
        report "Testing Layer 0 (FC1: 400->64)...";
        for idx in 0 to 9 loop
            -- Set up request
            pixel_index_0 <= idx;

            -- Apply address and wait fixed 2 cycles (controller/BRAM synchronous read)
            start_cycle := sim_cycle;
            wait for CLK_PERIOD * 2;
            latency := sim_cycle - start_cycle;
            if latency < 0 then
                latency := 0;
            end if;
            if latency > MAX_LATENCY then
                hist(MAX_LATENCY) := hist(MAX_LATENCY) + 1;
            else
                hist(latency) := hist(latency) + 1;
            end if;

            report "Loaded weights for input index " & integer'image(idx) & " (latency=" & integer'image(latency) & " cycles)";

            -- Display first few node weights for Layer 0
            for node in 0 to 7 loop
                report "  L0 Node " & integer'image(node) & " weight = " & integer'image(to_integer(signed(weight_data(node))));
                if has_unknown(weight_data(node)) then
                    report "ERROR: weight_data(" & integer'image(node) & ") contains unknown bits at input index " & integer'image(idx) severity failure;
                end if;
            end loop;

            -- Fail on excessive latency (likely BRAM handshake/timing bug)
            if latency > LATENCY_FAIL_THRESHOLD then
                report "ERROR: BRAM read latency too long (" & integer'image(latency) & " cycles) for input index " & integer'image(idx) severity failure;
            end if;

            wait for CLK_PERIOD;
        end loop;

        -- Test some middle indices
        for idx in 195 to 204 loop
            pixel_index_0 <= idx;
            start_cycle := sim_cycle;
            wait for CLK_PERIOD * 2;
            latency := sim_cycle - start_cycle;
            if latency < 0 then
                latency := 0;
            end if;
            if latency > MAX_LATENCY then
                hist(MAX_LATENCY) := hist(MAX_LATENCY) + 1;
            else
                hist(latency) := hist(latency) + 1;
            end if;

            report "Loaded weights for input index " & integer'image(idx) & " (latency=" & integer'image(latency) & " cycles)";

            -- Check for unknown bits
            for node in 0 to NUM_NODES_0-1 loop
                if has_unknown(weight_data(node)) then
                    report "ERROR: weight_data(" & integer'image(node) & ") contains unknown bits at input index " & integer'image(idx) severity failure;
                end if;
            end loop;

            if latency > LATENCY_FAIL_THRESHOLD then
                report "ERROR: BRAM read latency too long (" & integer'image(latency) & " cycles) for input index " & integer'image(idx) severity failure;
            end if;

            wait for CLK_PERIOD;
        end loop;

        -- Test last few indices
        for idx in 390 to 399 loop
            pixel_index_0 <= idx;
            start_cycle := sim_cycle;
            wait for CLK_PERIOD * 2;
            latency := sim_cycle - start_cycle;
            if latency < 0 then
                latency := 0;
            end if;
            if latency > MAX_LATENCY then
                hist(MAX_LATENCY) := hist(MAX_LATENCY) + 1;
            else
                hist(latency) := hist(latency) + 1;
            end if;

            report "Loaded weights for input index " & integer'image(idx) & " (latency=" & integer'image(latency) & " cycles)";

            -- Check for unknown bits
            for node in 0 to NUM_NODES_0-1 loop
                if has_unknown(weight_data(node)) then
                    report "ERROR: weight_data(" & integer'image(node) & ") contains unknown bits at input index " & integer'image(idx) severity failure;
                end if;
            end loop;

            if latency > LATENCY_FAIL_THRESHOLD then
                report "ERROR: BRAM read latency too long (" & integer'image(latency) & " cycles) for input index " & integer'image(idx) severity failure;
            end if;

            wait for CLK_PERIOD;
        end loop;

        -- Test Layer 1 (FC2): Test all 64 input indices
        report "Testing Layer 1 (FC2: 64->10)...";
        for idx in 0 to NUM_INPUTS_1-1 loop
            -- Set up request
            pixel_index_1 <= idx;

            -- Apply address and wait fixed 2 cycles (controller/BRAM synchronous read)
            start_cycle := sim_cycle;
            wait for CLK_PERIOD * 2;
            latency := sim_cycle - start_cycle;
            if latency < 0 then
                latency := 0;
            end if;
            if latency > MAX_LATENCY then
                hist(MAX_LATENCY) := hist(MAX_LATENCY) + 1;
            else
                hist(latency) := hist(latency) + 1;
            end if;

            report "Loaded weights for input index " & integer'image(idx) & " (latency=" & integer'image(latency) & " cycles)";

            -- Display all 10 node weights for Layer 1
            for node in 0 to NUM_NODES_1-1 loop
                report "  L1 Node " & integer'image(node) & " weight = " & integer'image(to_integer(signed(weight_data_1(node))));
                if has_unknown(weight_data_1(node)) then
                    report "ERROR: weight_data_1(" & integer'image(node) & ") contains unknown bits at input index " & integer'image(idx) severity failure;
                end if;
            end loop;

            -- Fail on excessive latency (likely BRAM handshake/timing bug)
            if latency > LATENCY_FAIL_THRESHOLD then
                report "ERROR: BRAM read latency too long (" & integer'image(latency) & " cycles) for input index " & integer'image(idx) severity failure;
            end if;

            wait for CLK_PERIOD;
        end loop;

        -- Print histogram
        report "Weight data latency histogram (cycles)";
        for i in 0 to MAX_LATENCY loop
            report "  cycles=" & integer'image(i) & " -> " & integer'image(hist(i));
        end loop;
        
        -- If any histogram bucket beyond our threshold has entries, fail the test
        for i in LATENCY_FAIL_THRESHOLD+1 to MAX_LATENCY loop
            if hist(i) > 0 then
                report "ERROR: Observed BRAM latency > " & integer'image(LATENCY_FAIL_THRESHOLD) & " cycles (hist bucket " & integer'image(i) & ")" severity failure;
            end if;
        end loop;

        report "Fully connected memory controller test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "Error: At " & integer'image(now / 1 ns) & " ns: TEST TIMEOUT - Fully connected memory controller test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;
