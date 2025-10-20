----------------------------------------------------------------------------------
-- Testbench for FC2 (Fully Connected Layer 2)
-- Tests: 64 inputs -> 10 outputs
-- Simple sequential input test
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity FC2_tb is
end FC2_tb;

architecture Behavioral of FC2_tb is

    -- Component Declaration
    component FC2
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            pixel_valid   : in  std_logic;
            pixel_data    : in  WORD;
            pixel_index   : in  integer range 0 to 63;
            output_valid  : out std_logic;
            output_data   : out WORD_ARRAY(0 to 9)
        );
    end component;

    -- Testbench signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal pixel_valid  : std_logic := '0';
    signal pixel_data   : WORD := (others => '0');
    signal pixel_index  : integer range 0 to 63 := 0;
    signal output_valid : std_logic;
    signal output_data  : WORD_ARRAY(0 to 9);

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
    uut: FC2
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
        report "=== Starting FC2 Testbench ===";
        rst <= '1';
        pixel_valid <= '0';
        wait for clk_period * 5;
        rst <= '0';
        wait for clk_period * 2;
        
        -- Test 2: Send 64 input neurons sequentially
        report "Test 1: Sending 64 input neurons with simple values";
        for i in 0 to 63 loop
            pixel_valid <= '1';
            pixel_index <= i;
            -- Use simple test pattern: pixel value = index * 2
            pixel_data <= std_logic_vector(to_unsigned((i * 2) mod 256, 8));
            wait for clk_period;
        end loop;
        pixel_valid <= '0';
        
        -- Wait for processing to complete (with timeout)
        report "Waiting for FC2 to complete processing...";
        for i in 0 to 30 loop
            wait for clk_period;
            if output_valid = '1' then
                exit;
            end if;
        end loop;
        
        -- Display results (all 10 outputs since there are only 10)
        report "FC2 output received! output_valid = " & std_logic'image(output_valid);
        report "All 10 class outputs:";
        for i in 0 to 9 loop
            report "  Class " & integer'image(i) & " score = " & 
                   integer'image(to_integer(unsigned(output_data(i))));
        end loop;
        
        wait for clk_period * 10;
        
        -- Test 3: Another test with different values
        report "Test 2: Sending inputs with alternating values";
        rst <= '1';
        wait for clk_period * 2;
        rst <= '0';
        wait for clk_period * 2;
        
        for i in 0 to 63 loop
            pixel_valid <= '1';
            pixel_index <= i;
            -- Alternating pattern: 100 or 200
            if (i mod 2 = 0) then
                pixel_data <= std_logic_vector(to_unsigned(100, 8));
            else
                pixel_data <= std_logic_vector(to_unsigned(200, 8));
            end if;
            wait for clk_period;
        end loop;
        pixel_valid <= '0';
        
        -- Wait with timeout
        for i in 0 to 30 loop
            wait for clk_period;
            if output_valid = '1' then
                exit;
            end if;
        end loop;
        
        report "Test 2 completed! output_valid = " & std_logic'image(output_valid);
        report "All 10 class outputs:";
        for i in 0 to 9 loop
            report "  Class " & integer'image(i) & " score = " & 
                   integer'image(to_integer(unsigned(output_data(i))));
        end loop;
        
        wait for clk_period * 10;
        
        -- Test 4: Test with all zeros
        report "Test 3: Sending all zero inputs";
        rst <= '1';
        wait for clk_period * 2;
        rst <= '0';
        wait for clk_period * 2;
        
        for i in 0 to 63 loop
            pixel_valid <= '1';
            pixel_index <= i;
            pixel_data <= (others => '0'); -- All zeros
            wait for clk_period;
        end loop;
        pixel_valid <= '0';
        
        -- Wait with timeout
        for i in 0 to 30 loop
            wait for clk_period;
            if output_valid = '1' then
                exit;
            end if;
        end loop;
        
        report "Test 3 completed! output_valid = " & std_logic'image(output_valid);
        report "All 10 class outputs with zero input:";
        for i in 0 to 9 loop
            report "  Class " & integer'image(i) & " score = " & 
                   integer'image(to_integer(unsigned(output_data(i))));
        end loop;
        
        wait for clk_period * 10;
        
        -- End simulation
        report "=== FC2 Testbench Complete ===";
        test_done <= true;
        wait;
    end process;

end Behavioral;
