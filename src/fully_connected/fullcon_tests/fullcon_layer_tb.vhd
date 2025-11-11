----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.04.2025
-- Design Name: Fully Connected Layer Testbench
-- Module Name: fullcon_layer_tb - Behavioral
-- Project Name: CNN Accelerator
-- Description: Testbench for modular fully connected layer
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

-- Required for file I/O operations
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
-- Optional: VHDL-2008 simulator control
use std.env.all;

entity fullcon_layer_tb is
end fullcon_layer_tb;

architecture Behavioral of fullcon_layer_tb is

    -- Test parameters
    -- FC1: 400 inputs -> 64 outputs (Layer 5)
    -- FC2: 64 inputs -> 10 outputs (Layer 6)
    constant FC1_INPUTS  : integer := 400;
    constant FC1_OUTPUTS : integer := 64;
    constant FC2_INPUTS  : integer := 64;
    constant FC2_OUTPUTS : integer := 10;
    
    -- Use reduced input count for faster testing
    constant TEST_FC1_INPUTS : integer := 400;  -- MUST match FC1_INPUTS for controller to work!
    constant TEST_FC2_INPUTS : integer := 64;   -- MUST match FC2_INPUTS for controller to work!
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals for FC1
    signal clk_fc1 : std_logic := '0';
    signal rst_fc1 : std_logic := '0';
    signal enable_fc1 : std_logic := '0';
    signal input_valid_fc1 : std_logic := '0';
    signal input_pixel_fc1 : WORD_16 := (others => '0');
    signal input_index_fc1 : integer range 0 to FC1_INPUTS-1 := 0;
    signal input_ready_fc1 : std_logic;
    signal output_valid_fc1 : std_logic;
    signal output_pixel_fc1 : WORD_ARRAY_16(0 to FC1_OUTPUTS-1);
    signal output_ready_fc1 : std_logic := '1';
    signal layer_done_fc1 : std_logic;
    
    -- UUT signals for FC2
    signal clk_fc2 : std_logic := '0';
    signal rst_fc2 : std_logic := '0';
    signal enable_fc2 : std_logic := '0';
    signal input_valid_fc2 : std_logic := '0';
    signal input_pixel_fc2 : WORD_16 := (others => '0');
    signal input_index_fc2 : integer range 0 to FC2_INPUTS-1 := 0;
    signal input_ready_fc2 : std_logic;
    signal output_valid_fc2 : std_logic;
    signal output_pixel_fc2 : WORD_ARRAY_16(0 to FC2_OUTPUTS-1);
    signal output_ready_fc2 : std_logic := '1';
    signal layer_done_fc2 : std_logic;
    
    -- Test control
    signal test_done : boolean := false;
    
    -- Helper function to generate test data
    function gen_pixel_value(index : integer) return WORD_16 is
        variable result : WORD_16;
    begin
        -- Generate pattern based on index
        -- Generate an 16-bit pattern and zero-extend to 16 bits by producing a 16-bit vector
        result := std_logic_vector(to_unsigned((index * 7 + 13) mod 256, 16));
        return result;
    end function;

begin

    -- Unit Under Test FC1 (Layer 5: 400->64)
    uut_fc1: entity work.fullcon_layer
        generic map (
            NODES_IN  => FC1_INPUTS,
            NODES_OUT => FC1_OUTPUTS,
            LAYER_ID  => 0
        )
        port map (
            clk          => clk_fc1,
            rst          => rst_fc1,
            enable       => enable_fc1,
            input_valid  => input_valid_fc1,
            input_pixel  => input_pixel_fc1,
            input_index  => input_index_fc1,
            input_ready  => input_ready_fc1,
            output_valid => output_valid_fc1,
            output_pixel => output_pixel_fc1,
            output_ready => output_ready_fc1,
            layer_done   => layer_done_fc1
        );

    -- Unit Under Test FC2 (Layer 6: 64->10)
    uut_fc2: entity work.fullcon_layer
        generic map (
            NODES_IN  => FC2_INPUTS,
            NODES_OUT => FC2_OUTPUTS,
            LAYER_ID  => 1
        )
        port map (
            clk          => clk_fc2,
            rst          => rst_fc2,
            enable       => enable_fc2,
            input_valid  => input_valid_fc2,
            input_pixel  => input_pixel_fc2,
            input_index  => input_index_fc2,
            input_ready  => input_ready_fc2,
            output_valid => output_valid_fc2,
            output_pixel => output_pixel_fc2,
            output_ready => output_ready_fc2,
            layer_done   => layer_done_fc2
        );

    -- Clock process (shared for both layers)
    clk_process: process
    begin
        report "Clock process starting...";
        while not test_done loop
            clk_fc1 <= '0';
            clk_fc2 <= '0';
            wait for CLK_PERIOD/2;
            clk_fc1 <= '1';
            clk_fc2 <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        report "Clock process stopped (test_done = true)";
        wait;
    end process;

    -- FC1 Output monitor
    fc1_output_monitor: process(clk_fc1)
        file debug_file : text open write_mode is "fc1_output_debug.txt";
        variable debug_line : line;
    begin
        if rising_edge(clk_fc1) then
            if output_valid_fc1 = '1' and output_ready_fc1 = '1' then
                report "FC1 Output valid";
                
                write(debug_line, string'("FC1_OUTPUT:"));
                writeline(debug_file, debug_line);
                
                for i in 0 to FC1_OUTPUTS-1 loop
                    report "  Node " & integer'image(i) & ": " & 
                        integer'image(to_integer(signed(output_pixel_fc1(i))));
                    
                    write(debug_line, string'("Node_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(output_pixel_fc1(i))));
                    writeline(debug_file, debug_line);
                end loop;
            end if;
        end if;
    end process;

    -- FC2 Output monitor
    fc2_output_monitor: process(clk_fc2)
        file debug_file : text open write_mode is "fc2_output_debug.txt";
        variable debug_line : line;
    begin
        if rising_edge(clk_fc2) then
            if output_valid_fc2 = '1' and output_ready_fc2 = '1' then
                report "FC2 Output valid (Classification)";
                
                write(debug_line, string'("FC2_OUTPUT (Classification):"));
                writeline(debug_file, debug_line);
                
                for i in 0 to FC2_OUTPUTS-1 loop
                    report "  Class " & integer'image(i) & ": " & 
                        integer'image(to_integer(signed(output_pixel_fc2(i))));
                    
                    write(debug_line, string'("Class_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(output_pixel_fc2(i))));
                    writeline(debug_file, debug_line);
                end loop;
            end if;
        end if;
    end process;

    -- Main test process
    test_process: process
    begin
        -- Initialize
        rst_fc1 <= '1';
        rst_fc2 <= '1';
        enable_fc1 <= '0';
        enable_fc2 <= '0';
        output_ready_fc1 <= '1';
        output_ready_fc2 <= '1';
        
        wait for CLK_PERIOD * 5;
        rst_fc1 <= '0';
        rst_fc2 <= '0';
        
        wait for CLK_PERIOD * 3;
        
        ------------------------------------------------------
        -- Test 1: FC1 Layer (400->64)
        ------------------------------------------------------
        report "========================================";
        report "Test 1: FC1 Layer (400->64)";
        report "========================================";
        
        enable_fc1 <= '1';
        wait for CLK_PERIOD;  -- Let enable propagate
        
        report "Sending " & integer'image(TEST_FC1_INPUTS) & " pixels to FC1...";
        report "input_ready_fc1 = " & std_logic'image(input_ready_fc1);
        
        -- Send input pixels
        for i in 0 to TEST_FC1_INPUTS-1 loop
            report "Loop iteration " & integer'image(i) & " starting...";
            
            -- Wait for ready (should already be '1', but check anyway)
            if input_ready_fc1 /= '1' then
                wait until input_ready_fc1 = '1';
            end if;
            report "  Ready signal confirmed";
            
            -- Set inputs and wait for next clock edge
            wait until rising_edge(clk_fc1);
            input_index_fc1 <= i;
            input_pixel_fc1 <= gen_pixel_value(i);
            input_valid_fc1 <= '1';
            report "  Signals set: index=" & integer'image(i) & " pixel=" & integer'image(to_integer(unsigned(gen_pixel_value(i))));
            
            -- Hold for one clock cycle
            wait until rising_edge(clk_fc1);
            input_valid_fc1 <= '0';
            report "  Valid deasserted";

            
            if i mod 50 = 0 then
                report "  Sent pixel " & integer'image(i) & " = " & integer'image(to_integer(unsigned(gen_pixel_value(i))));
            end if;
        end loop;
        
        report "All FC1 inputs sent, waiting for output...";
        
        -- Wait for layer done
        wait until layer_done_fc1 = '1';
        
        report "FC1 completed!";
        
        wait for CLK_PERIOD * 10;
        
        ------------------------------------------------------
        -- Test 2: FC2 Layer (64->10)
        ------------------------------------------------------
        report "========================================";
        report "Test 2: FC2 Layer (64->10)";
        report "========================================";
        
        enable_fc2 <= '1';
        wait for CLK_PERIOD;  -- Let enable propagate
        
        report "Sending " & integer'image(TEST_FC2_INPUTS) & " pixels to FC2...";
        report "input_ready_fc2 = " & std_logic'image(input_ready_fc2);
        
        -- Send input pixels
        for i in 0 to TEST_FC2_INPUTS-1 loop
            report "FC2 Loop iteration " & integer'image(i) & " starting...";
            
            -- Wait for ready (should already be '1', but check anyway)
            if input_ready_fc2 /= '1' then
                wait until input_ready_fc2 = '1';
            end if;
            report "  FC2 Ready signal confirmed";
            
            -- Set inputs and wait for next clock edge
            wait until rising_edge(clk_fc2);
            input_index_fc2 <= i;
            input_pixel_fc2 <= gen_pixel_value(i + 100);  -- Different offset
            input_valid_fc2 <= '1';
            report "  FC2 Signals set: index=" & integer'image(i) & " pixel=" & integer'image(to_integer(unsigned(gen_pixel_value(i + 100))));
            
            -- Hold for one clock cycle
            wait until rising_edge(clk_fc2);
            input_valid_fc2 <= '0';
            report "  FC2 Valid deasserted";
        end loop;
        
        report "All FC2 inputs sent, waiting for output...";
        
        -- Wait for layer done
        wait until layer_done_fc2 = '1';
        
        report "FC2 completed!";
        
        wait for CLK_PERIOD * 10;
        
        ------------------------------------------------------
        -- Test 3: FC1 Second Run (test restart)
        ------------------------------------------------------
        report "========================================";
        report "Test 3: FC1 Second Run";
        report "========================================";
        
        -- Reset and restart FC1
        rst_fc1 <= '1';
        wait for CLK_PERIOD * 2;
        rst_fc1 <= '0';
        wait for CLK_PERIOD * 2;
        
        enable_fc1 <= '1';
        
        -- Send inputs again with different values
        for i in 0 to TEST_FC1_INPUTS-1 loop
            wait until input_ready_fc1 = '1';
            
            input_index_fc1 <= i;
            input_pixel_fc1 <= gen_pixel_value(i + 50);
            input_valid_fc1 <= '1';
            
            wait until rising_edge(clk_fc1);
            input_valid_fc1 <= '0';
        end loop;
        
        wait until layer_done_fc1 = '1';
        
        report "FC1 second run completed!";
        
        wait for CLK_PERIOD * 10;
        
        ------------------------------------------------------
        -- Test complete
        ------------------------------------------------------
        report "========================================";
        report "All fully connected layer tests completed successfully!";
        report "========================================";
        
        test_done <= true;
        wait for CLK_PERIOD;
        std.env.stop(0);
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 100 ms;
        if not test_done then
            report "TEST TIMEOUT - Test did not complete within expected time" severity failure;
        end if;
        wait;
    end process;

end Behavioral;
