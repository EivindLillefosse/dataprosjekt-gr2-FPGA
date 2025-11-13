----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.03.2025
-- Design Name: Calculation Testbench
-- Module Name: calculation_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for calculation module (MAC array for fully connected layers)
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity calculation_tb is
end calculation_tb;

architecture Behavioral of calculation_tb is

    -- Test parameters
    constant NODES           : integer := 64;
    constant MAC_DATA_WIDTH  : integer := 16;
    constant MAC_RESULT_WIDTH: integer := 16;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal clear        : std_logic := '0';
    signal pixel_data   : std_logic_vector(MAC_DATA_WIDTH-1 downto 0) := (others => '0');
    signal weight_data  : WORD_ARRAY(0 to NODES-1);
    signal compute_en   : std_logic := '0';
    signal results      : WORD_ARRAY_16(0 to NODES-1);
    signal compute_done : std_logic_vector(NODES-1 downto 0);
    
    -- Test control
    signal test_done : boolean := false;

begin

    -- Unit Under Test
    uut: entity work.calculation
        generic map (
            NODES => NODES,
            MAC_DATA_WIDTH => MAC_DATA_WIDTH,
            MAC_RESULT_WIDTH => MAC_RESULT_WIDTH
        )
        port map (
            clk => clk,
            rst => rst,
            clear => clear,
            pixel_data => pixel_data,
            weight_data => weight_data,
            compute_en => compute_en,
            results => results,
            compute_done => compute_done
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
        -- temporaries for Q1.6 test
        variable res_signed : integer;
        variable expected_q : integer;
        variable raw_prod : integer;
        variable scaled_from_raw : integer;
    begin
        -- Initialize
        rst <= '1';
        clear <= '0';
        compute_en <= '0';
        pixel_data <= (others => '0');
        
        -- Initialize weight data
        for i in 0 to NODES-1 loop
            -- weight_data elements are type WORD (8 bits). Use WORD_SIZE for correct width.
            weight_data(i) <= std_logic_vector(to_unsigned(i + 1, WORD_SIZE)); -- Weights: 1, 2, 3, ..., 64
        end loop;
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting calculation module test...";
        
        -- Test case 1: Single computation
        report "Test 1: Single MAC computation";
        pixel_data <= std_logic_vector(to_unsigned(10, MAC_DATA_WIDTH)); -- Pixel value = 10
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';
        
        -- Wait for MAC computation to complete
        wait until compute_done = (compute_done'range => '1');

        wait for CLK_PERIOD;
        
        report "MAC computation completed";
        -- Check first few and last few results
        for i in 0 to 7 loop
            report "Node " & integer'image(i) & " result: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: 10 * (i+1) = 10, 20, 30, 40, 50, 60, 70, 80
            assert to_integer(unsigned(results(i))) = 10 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected result for node " & integer'image(i) & 
                       ", expected " & integer'image(10 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;
        
        for i in NODES-4 to NODES-1 loop
            report "Node " & integer'image(i) & " result: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: 10 * (i+1)
            assert to_integer(unsigned(results(i))) = 10 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected result for node " & integer'image(i) & 
                       ", expected " & integer'image(10 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 2: Multiple accumulations
        report "Test 2: Multiple accumulations";
        
        -- Second computation (should accumulate)
        pixel_data <= std_logic_vector(to_unsigned(5, MAC_DATA_WIDTH)); -- Pixel value = 5
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';
        
        wait until compute_done = (compute_done'range => '1');
        
        report "Second MAC computation completed";
        for i in 0 to 7 loop
            report "Node " & integer'image(i) & " accumulated result: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: previous + 5 * (i+1) = 10*(i+1) + 5*(i+1) = 15*(i+1)
            assert to_integer(unsigned(results(i))) = 15 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected accumulated result for node " & integer'image(i) & 
                       ", expected " & integer'image(15 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 3: Clear and restart
        report "Test 3: Clear and restart";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        
        wait for CLK_PERIOD * 2;
        
        -- New computation after clear
        pixel_data <= std_logic_vector(to_unsigned(3, MAC_DATA_WIDTH)); -- Pixel value = 3
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';
        
        wait until compute_done = (compute_done'range => '1');
        
        report "Computation after clear completed";
        for i in 0 to 7 loop
            report "Node " & integer'image(i) & " result after clear: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: 3 * (i+1) = 3, 6, 9, 12, 15, 18, 21, 24
            assert to_integer(unsigned(results(i))) = 3 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected result after clear for node " & integer'image(i) & 
                       ", expected " & integer'image(3 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 4: Zero pixel
        report "Test 4: Zero pixel value";
        pixel_data <= (others => '0'); -- Pixel value = 0
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';
        
        wait until compute_done = (compute_done'range => '1');
        
        report "Zero pixel computation completed";
        for i in 0 to 7 loop
            report "Node " & integer'image(i) & " result with zero pixel: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Should remain the same as previous (3 * (i+1))
            assert to_integer(unsigned(results(i))) = 3 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Result should not change with zero pixel for node " & integer'image(i) & 
                       ", expected " & integer'image(3 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;
        
        wait for CLK_PERIOD * 3;

        -- Test case 5: Signed Q1.6 inputs and Q1.6-formatted output
        report "Test 5: Signed Q1.6 input and Q1.6-format output check";
        -- Ensure accumulators are cleared first
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD * 2;

        -- Use pixel = -0.5 (Q1.6 => -0.5 * 64 = -32) and weight = +1.0 (Q1.6 => 64)
        pixel_data <= std_logic_vector(to_signed(-32, MAC_DATA_WIDTH)); -- -0.5 in Q1.6
        for i in 0 to NODES-1 loop
            -- 1.0 in Q1.6 = 64. Fit into WORD (8 bits) and use signed representation.
            weight_data(i) <= std_logic_vector(to_signed(64, WORD_SIZE)); -- 1.0 in Q1.6
        end loop;
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';

        -- Wait for MAC computation to complete
        wait until compute_done = (compute_done'range => '1');

        wait for CLK_PERIOD;

        report "Q1.6 MAC computation completed";
        for i in 0 to 7 loop
            -- Interpret results as signed integer
            res_signed := to_integer(signed(results(i)));
            -- Compute raw product (full-width) and expected Q1.6 scaled value
            raw_prod := to_integer(signed(pixel_data)) * to_integer(signed(weight_data(i)));
            expected_q := raw_prod / 64; -- Q1.6 expected (arithmetic shift)
            -- If DUT returned raw product (Q2.12), scaled_from_raw equals expected_q
            scaled_from_raw := res_signed / 64;

            if res_signed = expected_q then
                report "  Node " & integer'image(i) & " result matches Q1.6 expected: " & integer'image(res_signed);
            elsif res_signed = raw_prod then
                report "  Node " & integer'image(i) & " DUT returned raw product: " & integer'image(res_signed) &
                       " (scaled -> " & integer'image(scaled_from_raw) & ")";
            else
                report "  Node " & integer'image(i) & " result (signed int) : " & integer'image(res_signed) &
                       " expected Q1.6: " & integer'image(expected_q) & " raw_prod: " & integer'image(raw_prod);
                assert false
                    report "Error: At " & integer'image(now / 1 ns) & " ns: Q1.6 mismatch for node " & integer'image(i) &
                           ", expected Q1.6=" & integer'image(expected_q) & ", raw_prod=" & integer'image(raw_prod) &
                           " but got " & integer'image(res_signed)
                    severity error;
            end if;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 6: Simulate FC layer behavior (400 inputs -> 64 outputs scenario)
        report "Test 6: Simulating fully connected layer behavior";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Simulate multiple input accumulations (like processing 400 inputs)
        report "  Accumulating 10 sequential inputs...";
        for input_idx in 0 to 9 loop
            pixel_data <= std_logic_vector(to_unsigned(input_idx + 1, MAC_DATA_WIDTH));
            compute_en <= '1';
            wait for CLK_PERIOD;
            compute_en <= '0';
            wait until compute_done = (compute_done'range => '1');
            wait for CLK_PERIOD;
        end loop;
        
        report "  Accumulated results from 10 inputs:";
        for i in 0 to 7 loop
            report "  Node " & integer'image(i) & " accumulated result: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: sum of (1+2+3+...+10) * (i+1) = 55 * (i+1)
            assert to_integer(unsigned(results(i))) = 55 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected accumulated result for node " & integer'image(i) & 
                       ", expected " & integer'image(55 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;
        
        report "Calculation module test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 2 ms;
        if not test_done then
            report "Error: At " & integer'image(now / 1 ns) & " ns: TEST TIMEOUT - Calculation module test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;
