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
    constant NUM_FILTERS : integer := 8;
    constant KERNEL_SIZE : integer := 3;
    constant ADDR_WIDTH  : integer := 7;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal load_req    : std_logic := '0';
    signal kernel_row  : integer range 0 to KERNEL_SIZE-1 := 0;
    signal kernel_col  : integer range 0 to KERNEL_SIZE-1 := 0;
    signal weight_data : WORD_ARRAY(0 to NUM_FILTERS-1);
    signal data_valid  : std_logic;
    
    -- Test control
    signal test_done : boolean := false;
    -- Simulation cycle counter for latency measurement
    signal sim_cycle : integer := 0;

begin

    -- Unit Under Test
    uut: entity work.weight_memory_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            KERNEL_SIZE => KERNEL_SIZE,
            ADDR_WIDTH => ADDR_WIDTH
        )
        port map (
            clk => clk,
            rst => rst,
            load_req => load_req,
            kernel_row => kernel_row,
            kernel_col => kernel_col,
            weight_data => weight_data,
            data_valid => data_valid
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

    begin
        -- Initialize
        rst <= '1';
        load_req <= '0';
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting weight memory controller test...";
        
        -- Test loading weights for different kernel positions and measure latency

        -- Each load brings all 8 filter weights for that position
        for row in 0 to KERNEL_SIZE-1 loop
            for col in 0 to KERNEL_SIZE-1 loop
                -- Set up request
                kernel_row <= row;
                kernel_col <= col;

                -- Issue load request (pulse)
                start_cycle := sim_cycle;
                load_req <= '1';
                wait for CLK_PERIOD;
                load_req <= '0';

                -- Wait for data_valid and measure latency
                wait until data_valid = '1';
                latency := sim_cycle - start_cycle;
                if latency < 0 then
                    latency := 0;
                end if;
                if latency > MAX_LATENCY then
                    hist(MAX_LATENCY) := hist(MAX_LATENCY) + 1;
                else
                    hist(latency) := hist(latency) + 1;
                end if;

                report "Loaded weights for kernel position [" & integer'image(row) & "," & integer'image(col) & "] (latency=" & integer'image(latency) & " cycles)";

                -- Display all 8 filter weights
                for filter in 0 to NUM_FILTERS-1 loop
                    report "  Filter " & integer'image(filter) & " weight = " & 
                           integer'image(to_integer(signed(weight_data(filter))));
                end loop;

                wait for CLK_PERIOD;
            end loop;
        end loop;

        -- Print histogram
        report "Weight data_valid latency histogram (cycles)";
        for i in 0 to MAX_LATENCY loop
            report "  cycles=" & integer'image(i) & " -> " & integer'image(hist(i));
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