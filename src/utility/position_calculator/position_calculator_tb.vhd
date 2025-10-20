----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Position Calculator Testbench
-- Module Name: position_calculator_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for position calculator
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity position_calculator_tb is
end position_calculator_tb;

architecture Behavioral of position_calculator_tb is

    -- Test parameters
    constant IMAGE_SIZE  : integer := 28;
    constant KERNEL_SIZE : integer := 3;
    constant BLOCK_SIZE  : integer := 2;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal advance     : std_logic := '0';
    signal row         : integer;
    signal col         : integer;
    signal region_row  : integer range 0 to KERNEL_SIZE-1;
    signal region_col  : integer range 0 to KERNEL_SIZE-1;
    signal region_done : std_logic;
    signal layer_done  : std_logic;
    
    -- Test control
    signal test_done : boolean := false;
    signal advance_count : integer := 0;

begin

    -- Unit Under Test
    uut: entity work.position_calculator
        generic map (
            IMAGE_SIZE => IMAGE_SIZE,
            KERNEL_SIZE => KERNEL_SIZE,
            BLOCK_SIZE => BLOCK_SIZE
        )
        port map (
            clk => clk,
            rst => rst,
            advance => advance,
            row => row,
            col => col,
            region_row => region_row,
            region_col => region_col,
            region_done => region_done,
            layer_done => layer_done
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
        advance <= '0';
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting position calculator test...";
        report "Initial position: [" & integer'image(row) & "," & integer'image(col) & "]";
        report "Initial region: [" & integer'image(region_row) & "," & integer'image(region_col) & "]";
        
        -- Test advancing through a few positions
        for i in 1 to 50 loop  -- Test first 50 advances
            advance <= '1';
            wait for CLK_PERIOD;
            advance <= '0';
            
            advance_count <= advance_count + 1;
            
            report "Advance " & integer'image(i) & 
                   ": Position [" & integer'image(row) & "," & integer'image(col) & "]" &
                   " Region [" & integer'image(region_row) & "," & integer'image(region_col) & "]" &
                   " Region_done: " & std_logic'image(region_done) &
                   " Layer_done: " & std_logic'image(layer_done);
            
            -- Check bounds
            assert row >= 0 and row < IMAGE_SIZE 
                report "Error: At " & integer'image(now / 1 ns) & " ns: Row out of bounds, expected 0-" & integer'image(IMAGE_SIZE-1) & 
                       " but got " & integer'image(row) 
                severity error;
                
            assert col >= 0 and col < IMAGE_SIZE 
                report "Error: At " & integer'image(now / 1 ns) & " ns: Col out of bounds, expected 0-" & integer'image(IMAGE_SIZE-1) & 
                       " but got " & integer'image(col) 
                severity error;
                
            assert region_row >= 0 and region_row < KERNEL_SIZE 
                report "Error: At " & integer'image(now / 1 ns) & " ns: Region row out of bounds, expected 0-" & integer'image(KERNEL_SIZE-1) & 
                       " but got " & integer'image(region_row) 
                severity error;
                
            assert region_col >= 0 and region_col < KERNEL_SIZE 
                report "Error: At " & integer'image(now / 1 ns) & " ns: Region col out of bounds, expected 0-" & integer'image(KERNEL_SIZE-1) & 
                       " but got " & integer'image(region_col) 
                severity error;
            
            wait for CLK_PERIOD;
            
            -- Exit early if layer is done
            if layer_done = '1' then
                report "Layer completed after " & integer'image(i) & " advances";
                exit;
            end if;
        end loop;
        
        -- Test reset functionality
        report "Testing reset functionality...";
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;
        
        report "After reset: Position [" & integer'image(row) & "," & integer'image(col) & "]";
        
        assert row = 0 and col = 0 
            report "Error: At " & integer'image(now / 1 ns) & " ns: Position should reset to [0,0], but got [" & 
                   integer'image(row) & "," & integer'image(col) & "]" 
            severity error;
            
        assert region_row = 0 and region_col = 0 
            report "Error: At " & integer'image(now / 1 ns) & " ns: Region should reset to [0,0], but got [" & 
                   integer'image(region_row) & "," & integer'image(region_col) & "]" 
            severity error;
        
        report "Position calculator test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "Error: At " & integer'image(now / 1 ns) & " ns: TEST TIMEOUT - Position calculator test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;