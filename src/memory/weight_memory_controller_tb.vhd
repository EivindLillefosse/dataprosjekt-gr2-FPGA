----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Weight Memory Controller Testbench
-- Module Name: weight_memory_controller_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for weight memory controller
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity weight_memory_controller_tb is
end weight_memory_controller_tb;

architecture Behavioral of weight_memory_controller_tb is

    -- Test parameters
    constant KERNEL_SIZE : integer := 3;
    -- Layer 0 has 8 filters, Layer 1 has 16 filters in this test
    constant NUM_FILTERS_0 : integer := 8;
    constant NUM_FILTERS_1 : integer := 16;
    -- Input channel counts for each layer
    constant NUM_INPUT_CHANNELS_0 : integer := 1;
    constant NUM_INPUT_CHANNELS_1 : integer := 8;

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal kernel_row  : integer range 0 to KERNEL_SIZE-1 := 0;
    signal kernel_col  : integer range 0 to KERNEL_SIZE-1 := 0;
    -- Separate channel signals for each UUT to avoid range conflicts
    signal channel_0   : integer range 0 to NUM_INPUT_CHANNELS_0-1 := 0; -- for layer0
    signal channel_1   : integer range 0 to NUM_INPUT_CHANNELS_1-1 := 0; -- for layer1
    signal weight_data : WORD_ARRAY(0 to NUM_FILTERS_0-1);
    signal weight_data_1 : WORD_ARRAY(0 to NUM_FILTERS_1-1);
    
    -- Test control
    signal test_done : boolean := false;
    -- Simulation cycle counter for latency measurement
    signal sim_cycle : integer := 0;

begin

    -- Unit Under Test
    uut: entity work.weight_memory_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS_0,
            NUM_INPUT_CHANNELS => NUM_INPUT_CHANNELS_0,
            KERNEL_SIZE => KERNEL_SIZE,
            LAYER_ID    => 0
        )
        port map (
            clk => clk,
            kernel_row => kernel_row,
            kernel_col => kernel_col,
            channel => channel_0,
            weight_data => weight_data
        );

    -- Second instance to test alternative layer memory (LAYER_ID = 1)
    uut_layer1: entity work.weight_memory_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS_1,
            NUM_INPUT_CHANNELS => NUM_INPUT_CHANNELS_1,
            KERNEL_SIZE => KERNEL_SIZE,
            LAYER_ID    => 1
        )
        port map (
            clk => clk,
            kernel_row => kernel_row,
            kernel_col => kernel_col,
            channel => channel_1,
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
        
        report "Starting weight memory controller test...";
        
        -- Test loading weights for different kernel positions and measure latency

        -- Each load brings all filter weights for that position and channel
        for row in 0 to KERNEL_SIZE-1 loop
            for col in 0 to KERNEL_SIZE-1 loop
                -- Iterate channels for layer1 (layer0 has only channel 0)
                for ch in 0 to NUM_INPUT_CHANNELS_1-1 loop
                    -- Set up request
                    kernel_row <= row;
                    kernel_col <= col;
                    channel_0 <= 0;
                    channel_1 <= ch;

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

                    report "Loaded weights for kernel position [" & integer'image(row) & "," & integer'image(col) & "] channel=" & integer'image(ch) & " (latency=" & integer'image(latency) & " cycles)";

                    -- Display filter weights for Layer 0 (NUM_FILTERS_0)
                    for filter in 0 to NUM_FILTERS_0-1 loop
                        report "  L0 Filter " & integer'image(filter) & " weight = " & integer'image(to_integer(signed(weight_data(filter))));
                        if has_unknown(weight_data(filter)) then
                            report "ERROR: weight_data(" & integer'image(filter) & ") contains unknown bits at kernel position [" & integer'image(row) & "," & integer'image(col) & "] channel=" & integer'image(ch) severity failure;
                        end if;
                    end loop;

                    -- Display filter weights for Layer 1 (NUM_FILTERS_1)
                    for filter in 0 to NUM_FILTERS_1-1 loop
                        report "  L1 Filter " & integer'image(filter) & " weight = " & integer'image(to_integer(signed(weight_data_1(filter))));
                        if has_unknown(weight_data_1(filter)) then
                            report "ERROR: weight_data_1(" & integer'image(filter) & ") contains unknown bits at kernel position [" & integer'image(row) & "," & integer'image(col) & "] channel=" & integer'image(ch) severity failure;
                        end if;
                    end loop;

                    -- Fail on excessive latency (likely BRAM handshake/timing bug)
                    if latency > LATENCY_FAIL_THRESHOLD then
                        report "ERROR: BRAM read latency too long (" & integer'image(latency) & " cycles) for kernel position [" & integer'image(row) & "," & integer'image(col) & "] channel=" & integer'image(ch) severity failure;
                    end if;

                    wait for CLK_PERIOD;
                end loop;
            end loop;
        end loop;

        -- Print histogram
        report "Weight data_valid latency histogram (cycles)";
        for i in 0 to MAX_LATENCY loop
            report "  cycles=" & integer'image(i) & " -> " & integer'image(hist(i));
        end loop;
        
        -- If any histogram bucket beyond our threshold has entries, fail the test
        for i in LATENCY_FAIL_THRESHOLD+1 to MAX_LATENCY loop
            if hist(i) > 0 then
                report "ERROR: Observed BRAM latency > " & integer'image(LATENCY_FAIL_THRESHOLD) & " cycles (hist bucket " & integer'image(i) & ")" severity failure;
            end if;
        end loop;

        report "Weight memory controller test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "Error: At " & integer'image(now / 1 ns) & " ns: TEST TIMEOUT - Weight memory controller test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;