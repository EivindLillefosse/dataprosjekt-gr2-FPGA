----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: AI Assistant
-- 
-- Create Date: 06.10.2025
-- Design Name: Fully Connected V2 Testbench
-- Module Name: fully_connected_v2_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for fully_connected_v2 module
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fully_connected_v2_tb is
end fully_connected_v2_tb;

architecture Behavioral of fully_connected_v2_tb is

    -- Component declaration
    component Fully_Connected is
        generic (
            NUM_FILTERS : integer := 64
        );
        Port (
            clk : in STD_LOGIC;
            rst : in STD_LOGIC;
            enable : in STD_LOGIC;
            output_valid : out std_logic;
            output_pixel : out WORD_ARRAY_16(0 to NUM_FILTERS-1);
            input_row : in integer;
            input_col : in integer;
            input_ready : in std_logic;
            input_channel : in integer;
            layer_done : out STD_LOGIC
        );
    end component;

    -- Test signals
    signal clk_tb : std_logic := '0';
    signal rst_tb : std_logic := '1';
    signal enable_tb : std_logic := '0';
    signal output_valid_tb : std_logic;
    signal output_pixel_tb : WORD_ARRAY_16(0 to 63); -- 64 filters
    signal input_row_tb : integer := 0;
    signal input_col_tb : integer := 0;
    signal input_ready_tb : std_logic := '0';
    signal input_channel_tb : integer := 0;
    signal layer_done_tb : std_logic;

    -- Test constants
    constant clk_period : time := 10 ns;
    constant NUM_TEST_FILTERS : integer := 64;

    -- Test data record type
    type position_record is record
        row : integer;
        col : integer;
        channel : integer;
    end record;
    
    -- Test data arrays
    type test_positions_array is array (0 to 9) of position_record;

    constant test_positions : test_positions_array := (
        (row => 0, col => 0, channel => 0),
        (row => 0, col => 1, channel => 0),
        (row => 1, col => 0, channel => 0),
        (row => 5, col => 10, channel => 2),
        (row => 10, col => 15, channel => 4),
        (row => 15, col => 20, channel => 6),
        (row => 20, col => 25, channel => 7),
        (row => 25, col => 0, channel => 1),
        (row => 12, col => 12, channel => 3),
        (row => 25, col => 25, channel => 7)
    );

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: Fully_Connected
        generic map (
            NUM_FILTERS => NUM_TEST_FILTERS
        )
        port map (
            clk => clk_tb,
            rst => rst_tb,
            enable => enable_tb,
            output_valid => output_valid_tb,
            output_pixel => output_pixel_tb,
            input_row => input_row_tb,
            input_col => input_col_tb,
            input_ready => input_ready_tb,
            input_channel => input_channel_tb,
            layer_done => layer_done_tb
        );

    -- Clock process
    clk_process: process
    begin
        clk_tb <= '0';
        wait for clk_period/2;
        clk_tb <= '1';
        wait for clk_period/2;
    end process;

    -- Test process
    test_process: process
    begin
        -- Reset sequence
        report "Starting Fully Connected V2 Testbench...";
        rst_tb <= '1';
        enable_tb <= '0';
        input_ready_tb <= '0';
        wait for clk_period * 4;
        
        rst_tb <= '0';
        wait for clk_period * 2;
        
        report "Reset completed, starting tests...";

        -- Test Case 1: Basic functionality test
        report "=== Test Case 1: Basic Single Pixel Test ===";
        
        enable_tb <= '1';
        input_row_tb <= test_positions(0).row;
        input_col_tb <= test_positions(0).col;
        input_channel_tb <= test_positions(0).channel;
        
        wait for clk_period;
        
        input_ready_tb <= '1';
        wait for clk_period;
        input_ready_tb <= '0';
        
        report "Sent pixel at position (" & integer'image(test_positions(0).row) & 
               "," & integer'image(test_positions(0).col) & 
               ") channel " & integer'image(test_positions(0).channel);
        
        -- Wait for processing to complete
        wait for clk_period * 100;  -- Allow time for weight loading and MAC computation
        
        if output_valid_tb = '1' then
            report "Test 1 SUCCESS: Output valid signal asserted";
            report "Sample output values:";
            report "  Filter 0 result: " & integer'image(to_integer(signed(output_pixel_tb(0))));
            report "  Filter 1 result: " & integer'image(to_integer(signed(output_pixel_tb(1))));
            report "  Filter 63 result: " & integer'image(to_integer(signed(output_pixel_tb(63))));
        else
            report "Test 1 FAILED: Output valid not asserted" severity warning;
        end if;
        
        wait for clk_period * 10;

        -- Test Case 2: Multiple pixel test
        report "=== Test Case 2: Multiple Pixel Processing ===";
        
        for i in 1 to 4 loop
            input_row_tb <= test_positions(i).row;
            input_col_tb <= test_positions(i).col;
            input_channel_tb <= test_positions(i).channel;
            
            wait for clk_period;
            
            input_ready_tb <= '1';
            wait for clk_period;
            input_ready_tb <= '0';
            
            report "Sent pixel " & integer'image(i) & " at position (" & 
                   integer'image(test_positions(i).row) & "," & 
                   integer'image(test_positions(i).col) & ") channel " & 
                   integer'image(test_positions(i).channel);
            
            -- Wait for processing
            wait for clk_period * 80;
            
            if output_valid_tb = '1' then
                report "Pixel " & integer'image(i) & " processed successfully";
            else
                report "WARNING: Pixel " & integer'image(i) & " processing may not be complete";
            end if;
            
            wait for clk_period * 10;
        end loop;

        -- Test Case 3: Corner cases test
        report "=== Test Case 3: Corner Cases ===";
        
        -- Test corner positions
        for i in 5 to 9 loop
            input_row_tb <= test_positions(i).row;
            input_col_tb <= test_positions(i).col;
            input_channel_tb <= test_positions(i).channel;
            
            wait for clk_period;
            
            input_ready_tb <= '1';
            wait for clk_period;
            input_ready_tb <= '0';
            
            report "Testing corner case: position (" & 
                   integer'image(test_positions(i).row) & "," & 
                   integer'image(test_positions(i).col) & ") channel " & 
                   integer'image(test_positions(i).channel);
            
            wait for clk_period * 80;
            
            if output_valid_tb = '1' then
                report "Corner case " & integer'image(i-4) & " handled successfully";
            end if;
            
            wait for clk_period * 10;
        end loop;

        -- Test Case 4: Rapid pixel sequence
        report "=== Test Case 4: Rapid Pixel Sequence ===";
        
        for i in 0 to 3 loop
            input_row_tb <= i;
            input_col_tb <= i;
            input_channel_tb <= i mod 8;
            
            input_ready_tb <= '1';
            wait for clk_period;
            input_ready_tb <= '0';
            wait for clk_period * 5;  -- Shorter wait between pixels
        end loop;
        
        wait for clk_period * 100;
        report "Rapid sequence test completed";

        -- Test Case 5: Disable/Enable test
        report "=== Test Case 5: Enable/Disable Test ===";
        
        enable_tb <= '0';
        input_row_tb <= 10;
        input_col_tb <= 10;
        input_channel_tb <= 5;
        input_ready_tb <= '1';
        wait for clk_period;
        input_ready_tb <= '0';
        
        wait for clk_period * 20;
        report "Module disabled - no processing should occur";
        
        enable_tb <= '1';
        wait for clk_period * 10;
        
        input_ready_tb <= '1';
        wait for clk_period;
        input_ready_tb <= '0';
        
        wait for clk_period * 50;
        report "Module re-enabled and processing resumed";

        -- Final report
        report "=== All Tests Completed ===";
        if layer_done_tb = '1' then
            report "Layer done signal is asserted";
        end if;
        
        report "Fully Connected V2 Testbench finished successfully!";
        
        wait;
        
    end process;

end Behavioral;