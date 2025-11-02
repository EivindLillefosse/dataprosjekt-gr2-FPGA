----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 01.11.2025
-- Design Name: CNN Top-Level Testbench
-- Module Name: cnn_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: Testbench for CNN top-level module
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

-- Required for file I/O operations
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
-- Optional: VHDL-2008 simulator control (std.env). Some simulators support this to stop/finish simulation.
use std.env.all;

entity cnn_tb is
end cnn_tb;

architecture Behavioral of cnn_tb is
    -- Test parameters (matching CNN top-level)
    constant IMAGE_SIZE : integer := 28;
    
    -- Final output will be from CONV_2 with 16 filters
    constant FINAL_NUM_FILTERS : integer := 16;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk : STD_LOGIC := '0';
    signal rst : STD_LOGIC := '0';
    signal enable : STD_LOGIC := '0';
    
    signal input_valid : std_logic := '0';
    signal input_pixel : WORD_ARRAY(0 to 0) := (others => (others => '0'));
    signal input_row : integer := 0;
    signal input_col : integer := 0;
    signal input_ready : std_logic;
    
    signal output_valid : std_logic;
    signal output_pixel : WORD_ARRAY(0 to FINAL_NUM_FILTERS-1);
    signal output_row : integer;
    signal output_col : integer;
    signal output_ready : std_logic := '1';
    
    signal layer_done : STD_LOGIC;
    
    -- Test image data (28x28 image)
    type test_image_type is array (0 to IMAGE_SIZE-1, 0 to IMAGE_SIZE-1) of integer;
    
    -- Function to generate 28x28 test image (same pattern as Python)
    function generate_test_image return test_image_type is
        variable temp_image : test_image_type;
    begin
        -- Generate the same pattern as Python: (row + col + 1) mod 256
        for row in 0 to IMAGE_SIZE-1 loop
            for col in 0 to IMAGE_SIZE-1 loop
                temp_image(row, col) := (row + col + 1) mod 256;
            end loop;
        end loop;
        return temp_image;
    end function;
    
    -- Use generated function (guaranteed to match Python)
    constant test_image : test_image_type := generate_test_image;
    
    -- Test control signals
    signal test_done : boolean := false;

begin
    -- Unit Under Test (UUT) - CNN Top-Level
    uut: entity work.cnn_top
        generic map (
            IMAGE_SIZE => IMAGE_SIZE
        )
        port map (
            clk => clk,
            rst => rst,
            enable => enable,
            input_valid => input_valid,
            input_pixel => input_pixel,
            input_row => input_row,
            input_col => input_col,
            input_ready => input_ready,
            output_valid => output_valid,
            output_pixel => output_pixel,
            output_row => output_row,
            output_col => output_col,
            output_ready => output_ready,
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

    -- Input pixel provider process (combinatorial for same-cycle response)
    input_provider: process(input_ready, input_row, input_col)
    begin
        if input_ready = '1' then
            -- Check if the requested coordinates are valid
                if input_row >= 0 and input_row < IMAGE_SIZE and 
               input_col >= 0 and input_col < IMAGE_SIZE then
                input_pixel(0) <= std_logic_vector(to_unsigned(test_image(input_row, input_col), 8));
                input_valid <= '1';
            else
                -- Provide zero for out-of-bounds pixels (padding)
                input_pixel <= (others => (others => '0'));
                input_valid <= '1';
            end if;
        else
            input_valid <= '0';
        end if;
    end process;
    
    -- Monitor input requests (separate process for reporting)
    input_monitor: process(clk)
    begin
        if rising_edge(clk) then
            if input_ready = '1' and input_valid = '1' then
                if input_row >= 0 and input_row < IMAGE_SIZE and 
                   input_col >= 0 and input_col < IMAGE_SIZE then
                    report "Providing pixel [" & integer'image(input_row) & "," & integer'image(input_col) & 
                           "] = " & integer'image(test_image(input_row, input_col));
                else
                    report "Providing padding pixel [" & integer'image(input_row) & "," & integer'image(input_col) & "] = 0";
                end if;
            end if;
        end if;
    end process;

    -- Output monitor process with intermediate value capture
    output_monitor: process(clk)
        file debug_file : text open write_mode is "cnn_intermediate_debug.txt";
        variable debug_line : line;
    begin
        if rising_edge(clk) then
            -- Monitor input requests
            if input_ready = '1' then
                write(debug_line, string'("INPUT_REQUEST: ["));
                write(debug_line, input_row);
                write(debug_line, ',');
                write(debug_line, input_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor input provision
            if input_valid = '1' then
                write(debug_line, string'("INPUT_PROVIDED: ["));
                write(debug_line, input_row);
                write(debug_line, ',');
                write(debug_line, input_col);
                write(debug_line, string'("] "));
                write(debug_line, to_integer(signed(input_pixel(0))));
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor final outputs
            if output_valid = '1' and output_ready = '1' then
                report "CNN Output at position [" & integer'image(output_row) & "," & integer'image(output_col) & "]";
                
                -- CNN_OUTPUT header
                write(debug_line, string'("CNN_OUTPUT: ["));
                write(debug_line, output_row);
                write(debug_line, ',');
                write(debug_line, output_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
                
                for i in 0 to FINAL_NUM_FILTERS-1 loop
                    report "  Filter " & integer'image(i) & ": " & 
                        integer'image(to_integer(signed(output_pixel(i))));
                    -- Write filter output
                    write(debug_line, string'("Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(output_pixel(i))));
                    writeline(debug_file, debug_line);
                end loop;
            end if;
        end if;
    end process;

    -- Main test process
    test_process: process
    begin
        -- Initialize
        rst <= '1';
        enable <= '0';
        output_ready <= '1';
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting CNN top-level test...";
        report "Test image ready - first pixel value: " & integer'image(test_image(0,0));
        report "Test image pattern - corner values: [0,0]=" & integer'image(test_image(0,0)) & 
               " [0,27]=" & integer'image(test_image(0,27)) & 
               " [27,0]=" & integer'image(test_image(27,0)) & 
               " [27,27]=" & integer'image(test_image(27,27));
        
        -- Start the CNN
        enable <= '1';
        
        -- Wait for CNN to complete
        wait until layer_done = '1';
        
        report "CNN processing completed successfully!";
        
        -- Wait a few more cycles
        wait for CLK_PERIOD * 10;
        
        -- Test reset functionality
        report "Testing CNN reset functionality...";
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 5;
        
        -- Test multiple runs
        report "Testing second CNN run...";
        enable <= '1';
        
        wait until layer_done = '1';
        
        report "Second CNN run completed!";
        
        wait for CLK_PERIOD * 10;
        
    test_done <= true;
    report "All CNN tests completed successfully!";
    -- Allow signals to settle for one clock period
    wait for CLK_PERIOD;
    -- Explicitly stop simulation when the simulator supports VHDL-2008 std.env
    -- This forces immediate termination; remove/comment out if your simulator doesn't support std.env
    std.env.stop(0);
    wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        -- Simple watchdog pattern used by other testbenches in this repo
        wait for 2000 ms;  -- Longer timeout for full CNN
        if not test_done then
            report "CNN TEST TIMEOUT - Test did not complete within expected time" severity failure;
        end if;
        wait;
    end process;

end Behavioral;
