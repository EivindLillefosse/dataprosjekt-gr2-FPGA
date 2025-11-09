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
    constant IMAGE_SIZE  : integer := 12;
    constant KERNEL_SIZE : integer := 3;
    constant BLOCK_SIZE  : integer := 2;
    constant OUT_SIZE    : integer := IMAGE_SIZE - KERNEL_SIZE + 1;  -- 10x10 output
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal advance     : std_logic := '0';
    signal req_out_row : integer := 0;
    signal req_out_col : integer := 0;
    signal req_valid   : std_logic := '0';
    signal row         : integer;
    signal col         : integer;
    signal input_row   : integer;
    signal input_col   : integer;
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
            req_out_row => req_out_row,
            req_out_col => req_out_col,
            req_valid => req_valid,
            row => row,
            col => col,
            input_row => input_row,
            input_col => input_col,
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
        variable expected_input_row : integer;
        variable expected_input_col : integer;
    begin
        -- Initialize
        rst <= '1';
        advance <= '0';
        req_valid <= '0';
        req_out_row <= 0;
        req_out_col <= 0;
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting position calculator test...";
        report "Testing 12x12 input -> 10x10 output (3x3 kernel)";
        
        -- Test: Iterate through all 100 output positions in a 10x10 grid
        report "Test: Full 10x10 output grid iteration";
        
        for out_row in 0 to OUT_SIZE-1 loop
            for out_col in 0 to OUT_SIZE-1 loop
                -- Request this output position
                req_out_row <= out_row;
                req_out_col <= out_col;
                req_valid <= '1';
                wait for CLK_PERIOD;
                req_valid <= '0';
                wait for CLK_PERIOD;
                
                report "Output position [" & integer'image(out_row) & "," & integer'image(out_col) & "]";
                
                -- Verify position loaded correctly
                assert row = out_row and col = out_col
                    report "Error: Position should be [" & integer'image(out_row) & "," & integer'image(out_col) & 
                           "], got [" & integer'image(row) & "," & integer'image(col) & "]"
                    severity error;
                
                -- Iterate through the 3x3 kernel window (9 positions)
                for kernel_row in 0 to KERNEL_SIZE-1 loop
                    for kernel_col in 0 to KERNEL_SIZE-1 loop
                        expected_input_row := out_row + kernel_row;
                        expected_input_col := out_col + kernel_col;
                        
                        -- Verify current region position
                        assert region_row = kernel_row and region_col = kernel_col
                            report "Error: Region should be [" & integer'image(kernel_row) & "," & integer'image(kernel_col) & 
                                   "], got [" & integer'image(region_row) & "," & integer'image(region_col) & "]"
                            severity error;
                        
                        -- Verify input position calculation
                        assert input_row = expected_input_row and input_col = expected_input_col
                            report "Error: Input position should be [" & integer'image(expected_input_row) & 
                                   "," & integer'image(expected_input_col) & "], got [" & 
                                   integer'image(input_row) & "," & integer'image(input_col) & "]"
                            severity error;
                        
                        -- Verify input position is within valid range [0, IMAGE_SIZE-1]
                        assert input_row >= 0 and input_row < IMAGE_SIZE
                            report "Error: Input row " & integer'image(input_row) & " out of bounds [0," & 
                                   integer'image(IMAGE_SIZE-1) & "]"
                            severity error;
                        
                        assert input_col >= 0 and input_col < IMAGE_SIZE
                            report "Error: Input col " & integer'image(input_col) & " out of bounds [0," & 
                                   integer'image(IMAGE_SIZE-1) & "]"
                            severity error;
                        
                        -- Advance to next kernel position (except for last position)
                        if kernel_row /= KERNEL_SIZE-1 or kernel_col /= KERNEL_SIZE-1 then
                            advance <= '1';
                            wait for CLK_PERIOD;
                            advance <= '0';
                            wait for CLK_PERIOD;
                        end if;
                    end loop;
                end loop;
                
                -- Check region_done is asserted after completing 3x3 kernel
                assert region_done = '1'
                    report "Error: Region_done should be '1' after completing 3x3 kernel"
                    severity error;
                
                -- Move to next output position
                wait for CLK_PERIOD;
            end loop;
        end loop;
        
        report "Successfully iterated through all " & integer'image(OUT_SIZE * OUT_SIZE) & " output positions";
        report "Verified " & integer'image(OUT_SIZE * OUT_SIZE * KERNEL_SIZE * KERNEL_SIZE) & " input position calculations";
        
        -- Test reset functionality
        report "Test: Reset functionality";
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;
        
        report "After reset: Position [" & integer'image(row) & "," & integer'image(col) & "]";
        
        assert row = 0 and col = 0 
            report "Error: Position should reset to [0,0], but got [" & 
                   integer'image(row) & "," & integer'image(col) & "]" 
            severity error;
            
        assert region_row = 0 and region_col = 0 
            report "Error: Region should reset to [0,0], but got [" & 
                   integer'image(region_row) & "," & integer'image(region_col) & "]" 
            severity error;
        
        report "Position calculator test completed successfully!";
        report "All tests passed - request-based positioning works correctly";
        
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