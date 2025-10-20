----------------------------------------------------------------------------------
-- Testbench for FC1 (Fully Connected Layer 1)
-- Tests: 400 inputs -> 64 outputs
-- Simple sequential input test
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity FC1_tb is
end FC1_tb;

architecture Behavioral of FC1_tb is

    -- Component Declaration
    component FC1
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            pixel_valid   : in  std_logic;
            pixel_data    : in  WORD;
            pixel_index   : in  integer range 0 to 399;
            output_valid  : out std_logic;
            output_data   : out WORD_ARRAY(0 to 63)
        );
    end component;

    -- Testbench signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal pixel_valid  : std_logic := '0';
    signal pixel_data   : WORD := (others => '0');
    signal pixel_index  : integer range 0 to 399 := 0;
    signal output_valid : std_logic;
    signal output_data  : WORD_ARRAY(0 to 63);

    -- Clock period
    constant clk_period : time := 10 ns;
    
    -- Test control
    signal test_done : boolean := false;

begin

    -- Clock generation
    clk_process : process
    begin
        while not test_done loop
            clk <= '0';
            wait for clk_period/2;
            clk <= '1';
            wait for clk_period/2;
        end loop;
        wait;
    end process;

    -- Unit Under Test
    uut: FC1
        port map (
            clk          => clk,
            rst          => rst,
            pixel_valid  => pixel_valid,
            pixel_data   => pixel_data,
            pixel_index  => pixel_index,
            output_valid => output_valid,
            output_data  => output_data
        );

    -- Stimulus process
    stim_proc: process
    begin
        -- Test 1: Reset
        report "=== Starting FC1 Testbench ===";
        rst <= '1';
        pixel_valid <= '0';
        wait for clk_period * 5;
        rst <= '0';
        wait for clk_period * 2;
        
        -- Test 2: Send 400 input pixels sequentially
        report "Test 1: Sending 400 input pixels with simple values";
        for i in 0 to 399 loop
            pixel_valid <= '1';
            pixel_index <= i;
            -- Use simple test pattern: pixel value = index mod 256
            pixel_data <= std_logic_vector(to_unsigned(i mod 256, 8));
            wait for clk_period;
        end loop;
        pixel_valid <= '0';
        
        -- Wait for processing to complete (with timeout)
        report "Waiting for FC1 to complete processing...";
        for i in 0 to 50 loop
            wait for clk_period;
            if output_valid = '1' then
                exit;
            end if;
        end loop;
        
        -- Display results
        report "FC1 output received! output_valid = " & std_logic'image(output_valid);
        report "First few outputs:";
        for i in 0 to 9 loop
            report "  output_data(" & integer'image(i) & ") = " & 
                   integer'image(to_integer(unsigned(output_data(i))));
        end loop;
        
        wait for clk_period * 10;
        
        -- End simulation
        report "=== FC1 Testbench Complete ===";
        test_done <= true;
        wait;
    end process;

end Behavioral;
