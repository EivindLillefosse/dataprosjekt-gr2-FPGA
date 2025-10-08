----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: MAC Testbench
-- Module Name: MAC_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for MAC (Multiply-Accumulate) unit
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MAC_tb is
end MAC_tb;

architecture Behavioral of MAC_tb is

    -- Test parameters
    constant WIDTH_A : integer := 8;
    constant WIDTH_B : integer := 8;
    constant WIDTH_P : integer := 16;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- Test data types and constants
    type int_array is array (0 to 5) of integer;
    constant pixel_values  : int_array := (1, 2, 3, 4, 5, 6);
    constant weight_values : int_array := (1, 0, -1, 1, 0, -1);
    
    -- UUT signals
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '0';
    signal clear     : std_logic := '0';
    signal pixel_in  : std_logic_vector(WIDTH_A-1 downto 0) := (others => '0');
    signal weights   : std_logic_vector(WIDTH_B-1 downto 0) := (others => '0');
    signal valid     : std_logic := '0';
    signal result    : std_logic_vector(WIDTH_P-1 downto 0);
    signal done      : std_logic;
    
    -- Test control
    signal test_done : boolean := false;


begin

    -- Unit Under Test
    uut: entity work.MAC
        generic map (
            width_a => WIDTH_A,
            width_b => WIDTH_B,
            width_p => WIDTH_P
        )
        port map (
            clk      => clk,
            rst      => rst,
            pixel_in => pixel_in,
            weights  => weights,
            valid    => valid,
            clear    => clear,
            result   => result,
            done     => done
        );

    -- Clock process
    clk_process: process
    begin
        wait for CLK_PERIOD/2;
        clk <= not clk;
    end process;

    -- Test process
    test_process: process
        variable expected_acc : integer := 0;
    begin
        -- Initialize
        rst <= '1';
        valid <= '0';
        clear <= '0';
        pixel_in <= (others => '0');
        weights <= (others => '0');
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
    report "At " & integer'image(now / 1 ns) & " ns: Starting MAC test...";
        
        -- Test case 1: Basic accumulation with positive values
    report "At " & integer'image(now / 1 ns) & " ns: Test 1: Basic accumulation with positive values";
        expected_acc := 0;
        
        -- Compute: 1*1 + 2*2 + 3*3 = 1 + 4 + 9 = 14
        for i in 1 to 3 loop
            pixel_in <= std_logic_vector(to_signed(i, WIDTH_A));
            weights <= std_logic_vector(to_signed(i, WIDTH_B));
            valid <= '1';
            wait for CLK_PERIOD;
            
            wait until done = '1';
            valid <= '0';
            
            expected_acc := expected_acc + (i * i);
            
         report "At " & integer'image(now / 1 ns) & " ns:   Computation " & integer'image(i) & ": " & 
             integer'image(i) & " * " & integer'image(i) & 
             " -> accumulated result = " & integer'image(to_integer(signed(result)));
            
            assert to_integer(signed(result)) = expected_acc
                report "Error: At " & integer'image(now / 1 ns) & " ns: MAC result mismatch at computation " & integer'image(i) & 
                       ", expected " & integer'image(expected_acc) & " but got " & integer'image(to_integer(signed(result)))
                severity error;
            wait for CLK_PERIOD*2;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 2: Clear and restart
    report "At " & integer'image(now / 1 ns) & " ns: Test 2: Clear and restart accumulation";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        
        wait for CLK_PERIOD * 2;
        
        expected_acc := 0;
        
        -- Simple test after clear: 5*2 = 10
        pixel_in <= std_logic_vector(to_signed(5, WIDTH_A));
        weights <= std_logic_vector(to_signed(2, WIDTH_B));
        valid <= '1';
        wait for CLK_PERIOD;
        
        wait until done = '1';
        wait for CLK_PERIOD;
        valid <= '0';
        
        expected_acc := 10;
        
    report "At " & integer'image(now / 1 ns) & " ns:   After clear: 5 * 2 = " & integer'image(to_integer(signed(result)));
        
        assert to_integer(signed(result)) = expected_acc
            report "Error: At " & integer'image(now / 1 ns) & " ns: MAC result after clear mismatch" & 
                   ", expected " & integer'image(expected_acc) & " but got " & integer'image(to_integer(signed(result)))
            severity error;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 3: Mixed positive and negative values
    report "At " & integer'image(now / 1 ns) & " ns: Test 3: Mixed positive and negative values";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        expected_acc := 0;
        
        -- Test pattern: 1*1 + 2*0 + 3*(-1) + 4*1 + 5*0 + 6*(-1) = 1 + 0 - 3 + 4 + 0 - 6 = -4
        for i in 0 to 5 loop
            pixel_in <= std_logic_vector(to_signed(pixel_values(i), WIDTH_A));
            weights <= std_logic_vector(to_signed(weight_values(i), WIDTH_B));
            valid <= '1';
            wait for CLK_PERIOD;
            
            wait until done = '1';
            valid <= '0';
            
            expected_acc := expected_acc + (pixel_values(i) * weight_values(i));
            
         report "At " & integer'image(now / 1 ns) & " ns:   Computation " & integer'image(i) & ": " & 
             integer'image(pixel_values(i)) & " * " & integer'image(weight_values(i)) & 
             " -> accumulated result = " & integer'image(to_integer(signed(result)));
            
            assert to_integer(signed(result)) = expected_acc
                report "Error: At " & integer'image(now / 1 ns) & " ns: MAC result mismatch at computation " & integer'image(i) & 
                       ", expected " & integer'image(expected_acc) & " but got " & integer'image(to_integer(signed(result)))
                severity error;
            wait for CLK_PERIOD*2;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 4: Zero values
    report "At " & integer'image(now / 1 ns) & " ns: Test 4: Zero values";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        pixel_in <= (others => '0');
        weights <= std_logic_vector(to_signed(5, WIDTH_B));
        valid <= '1';
        wait for CLK_PERIOD;
        
        wait until done = '1';
        wait for CLK_PERIOD;
        valid <= '0';
        
    report "At " & integer'image(now / 1 ns) & " ns:   0 * 5 = " & integer'image(to_integer(signed(result)));
        
        assert to_integer(signed(result)) = 0
            report "Error: At " & integer'image(now / 1 ns) & " ns: Zero pixel should result in zero" & 
                   ", expected 0 but got " & integer'image(to_integer(signed(result)))
            severity error;
        
    report "At " & integer'image(now / 1 ns) & " ns: MAC test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "Error: At " & integer'image(now / 1 ns) & " ns: TEST TIMEOUT - MAC test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;