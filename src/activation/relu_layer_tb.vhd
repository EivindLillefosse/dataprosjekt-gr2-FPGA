----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: ReLU Layer Testbench
-- Module Name: relu_layer_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for ReLU activation layer
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity relu_layer_tb is
end relu_layer_tb;

architecture Behavioral of relu_layer_tb is

    -- Test parameters
    constant NUM_FILTERS : integer := 8;
    constant DATA_WIDTH  : integer := 16;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal data_in     : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    signal data_valid  : std_logic := '0';
    signal data_out    : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    signal valid_out   : std_logic;
    
    -- Test control
    signal test_done : boolean := false;

begin

    -- Unit Under Test
    uut: entity work.relu_layer
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk => clk,
            rst => rst,
            data_in => data_in,
            data_valid => data_valid,
            data_out => data_out,
            valid_out => valid_out
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
        data_valid <= '0';
        data_in <= (others => (others => '0'));
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting ReLU layer test...";
        
        -- Test case 1: All positive values
        report "Test 1: All positive values";
        for i in 0 to NUM_FILTERS-1 loop
            data_in(i) <= std_logic_vector(to_unsigned(100 + i * 10, DATA_WIDTH));
        end loop;
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        
        assert valid_out = '1' 
            report "Output should be valid for positive inputs at time " & time'image(now)
            severity error;
            
        for i in 0 to NUM_FILTERS-1 loop
            assert data_out(i) = data_in(i) 
                report "Positive values should pass through unchanged at time " & time'image(now)
                severity error;
            report "Filter " & integer'image(i) & ": " & 
                   integer'image(to_integer(unsigned(data_in(i)))) & " -> " &
                   integer'image(to_integer(unsigned(data_out(i))));
        end loop;
        
        wait for CLK_PERIOD * 2;
        
        -- Test case 2: All negative values (MSB = 1)
        report "Test 2: All negative values";
        for i in 0 to NUM_FILTERS-1 loop
            data_in(i) <= std_logic_vector(to_unsigned(32768 + i * 100, DATA_WIDTH)); -- MSB = 1
        end loop;
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        
        assert valid_out = '1' 
            report "Output should be valid for negative inputs at time " & time'image(now)
            severity error;
            
        for i in 0 to NUM_FILTERS-1 loop
            assert data_out(i) = (DATA_WIDTH-1 downto 0 => '0') 
                report "Negative values should be clamped to zero at time " & time'image(now)
                severity error;
            report "Filter " & integer'image(i) & ": " & 
                   integer'image(to_integer(unsigned(data_in(i)))) & " -> " &
                   integer'image(to_integer(unsigned(data_out(i))));
        end loop;
        
        wait for CLK_PERIOD * 2;
        
        -- Test case 3: Mixed positive and negative values
        report "Test 3: Mixed positive and negative values";
        for i in 0 to NUM_FILTERS-1 loop
            if i mod 2 = 0 then
                data_in(i) <= std_logic_vector(to_unsigned(50 + i * 5, DATA_WIDTH)); -- Positive
            else
                data_in(i) <= std_logic_vector(to_unsigned(40000 + i * 100, DATA_WIDTH)); -- Negative (MSB=1)
            end if;
        end loop;
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        
        assert valid_out = '1' 
            report "Output should be valid for mixed inputs at time " & time'image(now)
            severity error;
            
        for i in 0 to NUM_FILTERS-1 loop
            if i mod 2 = 0 then
                assert data_out(i) = data_in(i) 
                    report "Positive values should pass through unchanged at time " & time'image(now)
                    severity error;
            else
                assert data_out(i) = (DATA_WIDTH-1 downto 0 => '0') 
                    report "Negative values should be clamped to zero at time " & time'image(now)
                    severity error;
            end if;
            report "Filter " & integer'image(i) & ": " & 
                   integer'image(to_integer(unsigned(data_in(i)))) & " -> " &
                   integer'image(to_integer(unsigned(data_out(i))));
        end loop;
        
        wait for CLK_PERIOD * 2;
        
        -- Test case 4: No valid input
        report "Test 4: Testing invalid input";
        data_valid <= '0';
        wait for CLK_PERIOD * 3;
        
        assert valid_out = '0' 
            report "Output should not be valid when input is not valid at time " & time'image(now)
            severity error;
        
        report "ReLU layer test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "TEST TIMEOUT - ReLU layer test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;