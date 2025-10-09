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
    signal weight_data : std_logic_vector(63 downto 0);  -- 64 bits: 8 filters * 8 bits
    signal data_valid  : std_logic;
    signal load_done   : std_logic;
    
    -- Test control
    signal test_done : boolean := false;

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
            data_valid => data_valid,
            load_done => load_done
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

    -- Test process
    test_process: process
    begin
        -- Initialize
        rst <= '1';
        load_req <= '0';
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting weight memory controller test...";
        
        -- Test loading weights for different kernel positions
        -- Each load brings all 8 filter weights for that position
        for row in 0 to KERNEL_SIZE-1 loop
            for col in 0 to KERNEL_SIZE-1 loop
                
                -- Set up request
                kernel_row <= row;
                kernel_col <= col;
                
                -- Issue load request
                load_req <= '1';
                wait for CLK_PERIOD;
                load_req <= '0';
                
                -- Wait for completion
                wait until load_done = '1';
                
                -- Check that data is valid
                assert data_valid = '1' 
                    report "Error: At " & integer'image(now / 1 ns) & " ns: Data should be valid when load_done is asserted for position [" & 
                           integer'image(row) & "," & integer'image(col) & "]"
                    severity error;
                
                report "Loaded weights for kernel position [" & integer'image(row) & "," & integer'image(col) & "]";
                
                -- Display all 8 filter weights
                for filter in 0 to NUM_FILTERS-1 loop
                    report "  Filter " & integer'image(filter) & " weight = " & 
                           integer'image(to_integer(signed(weight_data((filter*8+7) downto (filter*8)))));
                end loop;
                
                wait for CLK_PERIOD;
            end loop;
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