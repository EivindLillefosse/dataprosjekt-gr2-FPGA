----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Convolution Engine Testbench
-- Module Name: convolution_engine_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for convolution engine (MAC array)
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity convolution_engine_tb is
end convolution_engine_tb;

architecture Behavioral of convolution_engine_tb is

    -- Test parameters
    constant NUM_FILTERS     : integer := 8;
    constant INPUT_CHANNELS  : integer := 4;
    constant MAC_DATA_WIDTH  : integer := 8;
    constant MAC_RESULT_WIDTH: integer := 16;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal clear        : std_logic := '0';
    signal pixel_data   : WORD_ARRAY(0 to INPUT_CHANNELS-1) := (others => (others => '0'));
    signal channel_index: integer range 0 to INPUT_CHANNELS-1 := 0;
    signal weight_data  : WORD_ARRAY(0 to NUM_FILTERS-1);
    signal compute_en   : std_logic := '0';
    signal results      : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    signal compute_done : std_logic_vector(NUM_FILTERS-1 downto 0);
    
    -- Test control
    signal test_done : boolean := false;

begin

    -- Unit Under Test
    uut: entity work.convolution_engine
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            INPUT_CHANNELS => INPUT_CHANNELS,
            MAC_DATA_WIDTH => MAC_DATA_WIDTH,
            MAC_RESULT_WIDTH => MAC_RESULT_WIDTH
        )
        port map (
            clk => clk,
            rst => rst,
            clear => clear,
            compute_en => compute_en,
            pixel_data => pixel_data,
            channel_index => channel_index,
            weight_data => weight_data,
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
        variable sum_pixels : integer;
    begin
    -- Initialize
    rst <= '1';
    clear <= '0';
    compute_en <= '0';
    pixel_data <= (others => (others => '0'));

        -- Initialize weight data
        for i in 0 to NUM_FILTERS-1 loop
            weight_data(i) <= std_logic_vector(to_unsigned(i + 1, MAC_DATA_WIDTH)); -- Weights: 1, 2, 3, ...
        end loop;

        wait for CLK_PERIOD * 2;
        rst <= '0';

        wait for CLK_PERIOD * 2;

        report "Starting convolution engine test...";

        -- Helper: pulse compute_en for one clock
        -- Test case 1: Single computation
        report "Test 1: Single MAC computation";
    -- Use channel 0 for the single-channel style tests
    pixel_data <= (others => (others => '0'));
    pixel_data(0) <= std_logic_vector(to_unsigned(10, MAC_DATA_WIDTH)); -- Pixel value = 10 on channel 0
    channel_index <= 0;
    compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';

        -- Wait until all MACs assert done
        wait until compute_done = (compute_done'range => '1');
        -- Sample results half a clock period after done
        wait for CLK_PERIOD/2;

        report "MAC computation completed";
        for i in 0 to NUM_FILTERS-1 loop
            report "Filter " & integer'image(i) & " result: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: 10 * (i+1) = 10, 20, 30, 40, 50, 60, 70, 80
            assert to_integer(unsigned(results(i))) = 10 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected result for filter " & integer'image(i) & 
                       ", expected " & integer'image(10 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;

        wait for CLK_PERIOD * 3;

        -- Test case 2: Multiple accumulations
        report "Test 2: Multiple accumulations";
    pixel_data <= (others => (others => '0'));
    pixel_data(0) <= std_logic_vector(to_unsigned(5, MAC_DATA_WIDTH)); -- Pixel value = 5 on channel 0
    channel_index <= 0;
    compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';

        wait until compute_done = (compute_done'range => '1');
        wait for CLK_PERIOD;

        report "Second MAC computation completed";
        for i in 0 to NUM_FILTERS-1 loop
            report "Filter " & integer'image(i) & " accumulated result: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: previous + 5 * (i+1) = 10*(i+1) + 5*(i+1) = 15*(i+1)
            assert to_integer(unsigned(results(i))) = 15 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected accumulated result for filter " & integer'image(i) & 
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

    -- New computation after clear (channel 0)
    pixel_data <= (others => (others => '0'));
    pixel_data(0) <= std_logic_vector(to_unsigned(3, MAC_DATA_WIDTH)); -- Pixel value = 3 on channel 0
    channel_index <= 0;
    compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';

        wait until compute_done = (compute_done'range => '1');
        wait for CLK_PERIOD/2;

        report "Computation after clear completed";
        for i in 0 to NUM_FILTERS-1 loop
            report "Filter " & integer'image(i) & " result after clear: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Expected: 3 * (i+1) = 3, 6, 9, 12, 15, 18, 21, 24
            assert to_integer(unsigned(results(i))) = 3 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Unexpected result after clear for filter " & integer'image(i) & 
                       ", expected " & integer'image(3 * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;

        wait for CLK_PERIOD * 3;

        -- Test case 4: Zero pixel
        report "Test 4: Zero pixel value";
    pixel_data <= (others => (others => '0')); -- Pixel value = 0 on all channels
    compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';

        wait until compute_done = (compute_done'range => '1');
        wait for CLK_PERIOD/2;

        report "Zero pixel computation completed";
        for i in 0 to NUM_FILTERS-1 loop
            report "Filter " & integer'image(i) & " result with zero pixel: " & 
                   integer'image(to_integer(unsigned(results(i))));
            -- Should remain the same as previous (3 * (i+1))
            assert to_integer(unsigned(results(i))) = 3 * (i + 1)
                report "Error: At " & integer'image(now / 1 ns) & " ns: Result should not change with zero pixel for filter " & integer'image(i) & 
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
        pixel_data <= (others => (others => '0'));
        pixel_data(0) <= std_logic_vector(to_signed(-32, MAC_DATA_WIDTH)); -- -0.5 in Q1.6 on channel 0
        channel_index <= 0;
        for i in 0 to NUM_FILTERS-1 loop
            weight_data(i) <= std_logic_vector(to_signed(64, MAC_DATA_WIDTH)); -- 1.0 in Q1.6
        end loop;
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';

        -- Wait for MAC computation to complete
        wait until compute_done = (compute_done'range => '1');
        -- Sample results half a clock period after done
        wait for CLK_PERIOD/2;

        report "Q1.6 MAC computation completed";
        for i in 0 to NUM_FILTERS-1 loop
            -- Interpret results as signed integer
            res_signed := to_integer(signed(results(i)));
            -- Compute raw product (full-width) and expected Q1.6 scaled value
            raw_prod := to_integer(signed(pixel_data(channel_index))) * to_integer(signed(weight_data(i)));
            expected_q := raw_prod / 64; -- Q1.6 expected (arithmetic shift)
            -- If DUT returned raw product (Q2.12), scaled_from_raw equals expected_q
            scaled_from_raw := res_signed / 64;

            if res_signed = expected_q then
                report "  Filter " & integer'image(i) & " result matches Q1.6 expected: " & integer'image(res_signed);
            elsif res_signed = raw_prod then
                report "  Filter " & integer'image(i) & " DUT returned raw product: " & integer'image(res_signed) &
                       " (scaled -> " & integer'image(scaled_from_raw) & ")";
            else
          report "  Filter " & integer'image(i) & " result (signed int) : " & integer'image(res_signed) &
              " expected Q1.6: " & integer'image(expected_q) & " raw_prod: " & integer'image(raw_prod);
                assert false
                    report "Error: At " & integer'image(now / 1 ns) & " ns: Q1.6 mismatch for filter " & integer'image(i) &
                           ", expected Q1.6=" & integer'image(expected_q) & ", raw_prod=" & integer'image(raw_prod) &
                           " but got " & integer'image(res_signed)
                    severity error;
            end if;
        end loop;

        report "Convolution engine test completed successfully!";

        wait for CLK_PERIOD * 10;
        -- Additional Test: multi-channel accumulation
        report "Test 6: Multi-channel accumulation across INPUT_CHANNELS";
        -- Clear accumulators
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD * 2;

        -- Set weights to (i+1) and pixels per channel to distinct values 1..INPUT_CHANNELS
        for i in 0 to NUM_FILTERS-1 loop
            weight_data(i) <= std_logic_vector(to_signed(i + 1, MAC_DATA_WIDTH));
        end loop;
        for ch in 0 to INPUT_CHANNELS-1 loop
            pixel_data(ch) <= std_logic_vector(to_signed(ch + 1, MAC_DATA_WIDTH));
        end loop;
        -- Stream through channels, issuing a compute for each
        for ch in 0 to INPUT_CHANNELS-1 loop
            channel_index <= ch;
            compute_en <= '1';
            wait for CLK_PERIOD;
            compute_en <= '0';
            wait until compute_done = (compute_done'range => '1');
            wait for CLK_PERIOD/2;
        end loop;

        -- Verify accumulated result: sum_{ch}(ch+1) * (i+1) = (INPUT_CHANNELS*(INPUT_CHANNELS+1)/2) * (i+1)
        sum_pixels := (INPUT_CHANNELS * (INPUT_CHANNELS + 1)) / 2;
        for i in 0 to NUM_FILTERS-1 loop
            assert to_integer(unsigned(results(i))) = sum_pixels * (i + 1)
                report "Error: Multi-channel accumulation mismatch for filter " & integer'image(i) &
                       ", expected " & integer'image(sum_pixels * (i + 1)) & " but got " & integer'image(to_integer(unsigned(results(i))))
                severity error;
        end loop;

        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 2 ms;
        if not test_done then
            report "Error: At " & integer'image(now / 1 ns) & " ns: TEST TIMEOUT - Convolution engine test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;