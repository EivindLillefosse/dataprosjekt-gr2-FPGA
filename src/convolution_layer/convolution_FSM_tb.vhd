----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: Convolution Layer Testbench
-- Module Name: conv_layer_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: Testbench for convolution layer FSM
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

entity conv_layer_tb is
end conv_layer_tb;

architecture Behavioral of conv_layer_tb is
    -- Test parameters
    constant IMAGE_SIZE : integer := 9;  -- Smaller image for testing
    constant KERNEL_SIZE : integer := 3;
    constant INPUT_CHANNELS : integer := 1;
    constant NUM_FILTERS : integer := 8;  -- Fewer filters for easier testing
    constant STRIDE : integer := 1;
    constant BLOCK_SIZE : integer := 2;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk : STD_LOGIC := '0';
    signal rst : STD_LOGIC := '0';
    signal enable : STD_LOGIC := '0';
    
    signal input_valid : std_logic := '0';
    signal input_pixel : WORD := (others => '0');
    signal input_row : integer := 0;
    signal input_col : integer := 0;
    signal input_ready : std_logic;
    
    signal output_valid : std_logic;
    signal output_pixel : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    signal output_row : integer;
    signal output_col : integer;
    signal output_ready : std_logic := '1';
    
    signal layer_done : STD_LOGIC;
    
    -- Test image data (28x28 image)
    type test_image_type is array (0 to IMAGE_SIZE-1, 0 to IMAGE_SIZE-1) of integer;
    
    -- Function to generate 28x28 test image
    function generate_test_image return test_image_type is
        variable temp_image : test_image_type;
    begin
        for row in 0 to IMAGE_SIZE-1 loop
            for col in 0 to IMAGE_SIZE-1 loop
                -- Create a simple pattern: row + col + 1 (mod 256)
                -- This creates a diagonal gradient pattern
                temp_image(row, col) := (row + col + 1) mod 256;
            end loop;
        end loop;
        return temp_image;
    end function;
    
    constant test_image : test_image_type := generate_test_image;
    
    -- Test control signals
    signal test_done : boolean := false;
    signal pixel_request_row : integer := 0;
    signal pixel_request_col : integer := 0;
    
    -- Debug signal for MAC intermediate values
    signal debug_mac_results : WORD_ARRAY_16(0 to NUM_FILTERS-1);

begin
    -- Unit Under Test (UUT)
    uut: entity work.conv_layer
        generic map (
            IMAGE_SIZE => IMAGE_SIZE,
            KERNEL_SIZE => KERNEL_SIZE,
            INPUT_CHANNELS => INPUT_CHANNELS,
            NUM_FILTERS => NUM_FILTERS,
            STRIDE => STRIDE,
            BLOCK_SIZE => BLOCK_SIZE
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

    -- Input pixel provider process
    input_provider: process(clk, rst)
    begin
        if rst = '1' then
            input_valid <= '0';
            input_pixel <= (others => '0');
        elsif rising_edge(clk) then
            if input_ready = '1' then
                -- Check if the requested coordinates are valid
                if input_row >= 0 and input_row < IMAGE_SIZE and 
                   input_col >= 0 and input_col < IMAGE_SIZE then
                    input_pixel <= std_logic_vector(to_unsigned(test_image(input_row, input_col), 8));
                    input_valid <= '1';
                    report "Providing pixel [" & integer'image(input_row) & "," & integer'image(input_col) & 
                           "] = " & integer'image(test_image(input_row, input_col));
                else
                    -- Provide zero for out-of-bounds pixels (padding)
                    input_pixel <= (others => '0');
                    input_valid <= '1';
                    report "Providing padding pixel [" & integer'image(input_row) & "," & integer'image(input_col) & "] = 0";
                end if;
            else
                input_valid <= '0';
            end if;
        end if;
    end process;

    -- Output monitor process with intermediate value capture
    output_monitor: process(clk)
        file debug_file : text open write_mode is "intermediate_debug.txt";
        variable debug_line : line;
    begin
        if rising_edge(clk) then
            -- Monitor input requests
            if input_ready = '1' then
                write(debug_line, string'("INPUT_REQUEST: ["));
                write(debug_line, input_row);
                write(debug_line, string'(","));
                write(debug_line, input_col);
                write(debug_line, string'("]"));
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor input provision
            if input_valid = '1' then
                write(debug_line, string'("INPUT_PROVIDED: ["));
                write(debug_line, input_row);
                write(debug_line, string'(","));
                write(debug_line, input_col);
                write(debug_line, string'("] = "));
                write(debug_line, to_integer(unsigned(input_pixel)));
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor final outputs
            if output_valid = '1' and output_ready = '1' then
                report "Output at position [" & integer'image(output_row) & "," & integer'image(output_col) & "]";
                
                write(debug_line, string'("OUTPUT: ["));
                write(debug_line, output_row);
                write(debug_line, string'(","));
                write(debug_line, output_col);
                write(debug_line, string'("]"));
                writeline(debug_file, debug_line);
                
                for i in 0 to NUM_FILTERS-1 loop
                    report "  Filter " & integer'image(i) & ": " & 
                           integer'image(to_integer(unsigned(output_pixel(i))));
                    
                    write(debug_line, string'("Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(unsigned(output_pixel(i))));
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
        
        report "Starting convolution layer test...";
        
        -- Start the convolution
        enable <= '1';
        
        -- Wait for layer to complete
        wait until layer_done = '1';
        
        report "Convolution layer completed successfully!";
        
        -- Wait a few more cycles
        wait for CLK_PERIOD * 10;
        
        -- Test reset functionality
        report "Testing reset functionality...";
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 5;
        
        -- Test multiple runs
        report "Testing second convolution run...";
        enable <= '1';
        
        wait until layer_done = '1';
        
        report "Second convolution completed!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        report "All tests completed successfully!";
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 10 ms;  -- Timeout after 10ms
        if not test_done then
            report "TEST TIMEOUT - Test did not complete within expected time" severity failure;
        end if;
        wait;
    end process;

end Behavioral;