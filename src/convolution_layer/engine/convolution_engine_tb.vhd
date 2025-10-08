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
    constant MAC_DATA_WIDTH  : integer := 8;
    constant MAC_RESULT_WIDTH: integer := 16;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal clear        : std_logic := '0';
    signal pixel_data   : std_logic_vector(MAC_DATA_WIDTH-1 downto 0) := (others => '0');
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
    begin
        -- Initialize
        rst <= '1';
        clear <= '0';
        compute_en <= '0';
        pixel_data <= (others => '0');
        
        -- Initialize weight data
        for i in 0 to NUM_FILTERS-1 loop
            weight_data(i) <= std_logic_vector(to_unsigned(i + 1, MAC_DATA_WIDTH)); -- Weights: 1, 2, 3, ...
        end loop;
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting convolution engine test...";
        
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
        
        -- Second computation (should accumulate)
        pixel_data <= std_logic_vector(to_unsigned(5, MAC_DATA_WIDTH)); -- Pixel value = 5
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';
        
        wait until compute_done = (compute_done'range => '1');
        
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
        
        -- New computation after clear
        pixel_data <= std_logic_vector(to_unsigned(3, MAC_DATA_WIDTH)); -- Pixel value = 3
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';
        
        wait until compute_done = (compute_done'range => '1');
        
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
        pixel_data <= (others => '0'); -- Pixel value = 0
        compute_en <= '1';
        wait for CLK_PERIOD;
        compute_en <= '0';
        
        wait until compute_done = (compute_done'range => '1');
        
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
        
        report "Convolution engine test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
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