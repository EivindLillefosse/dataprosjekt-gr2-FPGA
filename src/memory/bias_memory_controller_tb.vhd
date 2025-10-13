----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 12.10.2025
-- Design Name: Bias Memory Controller Testbench
-- Module Name: bias_memory_controller_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for bias memory controller
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity bias_memory_controller_tb is
end bias_memory_controller_tb;

architecture Behavioral of bias_memory_controller_tb is

    -- Test parameters
    constant NUM_FILTERS : integer := 8;
    constant ADDR_WIDTH  : integer := 3;
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- UUT signals
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal load_req    : std_logic := '0';
    signal filter_idx  : integer range 0 to NUM_FILTERS-1 := 0;
    signal bias_data   : std_logic_vector(7 downto 0);
    signal data_valid  : std_logic;
    -- load_done removed; use data_valid

    -- Test control
    signal test_done : boolean := false;
    signal sim_cycle : integer := 0;

begin

    -- Unit Under Test
    uut: entity work.bias_memory_controller
        generic map (
        -- Simulation cycle counter for latency measurement

            NUM_FILTERS => NUM_FILTERS,
            ADDR_WIDTH => ADDR_WIDTH
        )
        port map (
            clk => clk,
            rst => rst,
            load_req => load_req,
            filter_idx => filter_idx,
            bias_data => bias_data,
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

    -- Simple cycle counter (concurrent process, not nested)
    cycle_counter: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sim_cycle <= 0;
            else
                sim_cycle <= sim_cycle + 1;
            end if;
        end if;
    end process;

    -- Test process
    test_process: process
    begin
        -- Initialize
        rst <= '1';
        load_req <= '0';

        wait for CLK_PERIOD * 2;
        rst <= '0';

        wait for CLK_PERIOD * 2;

        report "Starting bias memory controller test...";

        -- Test loading biases for each filter
        for idx in 0 to NUM_FILTERS-1 loop
            filter_idx <= idx;
            -- Issue load request (pulse)
            load_req <= '1';
            wait for CLK_PERIOD;
            load_req <= '0';

            -- Wait until data is valid
            wait until data_valid = '1';

            report "Loaded bias for filter " & integer'image(idx) & " = " & integer'image(to_integer(signed(bias_data)));

            wait for CLK_PERIOD;
        end loop;

        report "Bias memory controller test completed successfully!";

        wait for CLK_PERIOD * 10;
    end process;
    
    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 3 ms;
        if not test_done then
            report "Error: At " & integer'image(integer(now / 1 ns)) & " ns: TEST TIMEOUT - Bias memory controller test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;
