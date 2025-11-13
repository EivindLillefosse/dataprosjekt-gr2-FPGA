----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.04.2025
-- Design Name: Fully Connected Layer
-- Module Name: Calc Index Testbench
-- Project Name: CNN Accelerator
-- Description: Testbench for calc_index module
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity calc_index_tb is
end calc_index_tb;

architecture Behavioral of calc_index_tb is

    -- Component declaration
    component calc_index is
        generic (
            NODES_IN       : integer := 400;
            INPUT_CHANNELS : integer := 16;
            INPUT_SIZE     : integer := 5
        );
        port (
            clk     : in  std_logic;
            rst     : in  std_logic;
            enable  : in  std_logic;
            
            req_row     : out integer range 0 to INPUT_SIZE-1;
            req_col     : out integer range 0 to INPUT_SIZE-1;
            req_valid   : out std_logic;
            
            pool_pixel_data  : in  WORD_ARRAY_16(0 to INPUT_CHANNELS-1);
            pool_pixel_valid : in  std_logic;
            pool_pixel_ready : out std_logic;
            
            fc_pixel_out    : out WORD_16;
            fc_pixel_valid  : out std_logic;
            fc_pixel_ready  : in  std_logic;
            
            curr_index  : out integer range 0 to NODES_IN-1;
            done        : out std_logic
        );
    end component;

    -- Constants
    constant CLK_PERIOD : time := 10 ns;
    constant NODES_IN : integer := 400;
    constant INPUT_CHANNELS : integer := 16;
    constant INPUT_SIZE : integer := 5;

    -- Signals
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '0';
    signal enable  : std_logic := '0';
    
    signal req_row     : integer range 0 to INPUT_SIZE-1;
    signal req_col     : integer range 0 to INPUT_SIZE-1;
    signal req_valid   : std_logic;
    
    signal pool_pixel_data  : WORD_ARRAY_16(0 to INPUT_CHANNELS-1) := (others => (others => '0'));
    signal pool_pixel_valid : std_logic := '0';
    signal pool_pixel_ready : std_logic;
    
    signal fc_pixel_out    : WORD_16;
    signal fc_pixel_valid  : std_logic;
    signal fc_pixel_ready  : std_logic := '1';  -- Default ready
    
    signal curr_index  : integer range 0 to NODES_IN-1;
    signal done        : std_logic;
    
    -- Test control
    signal test_running : boolean := true;

    -- Helper function to generate test pixel data based on position and channel
    function gen_pixel_value(row : integer; col : integer; channel : integer) return WORD_16 is
        variable temp : integer;
    begin
        temp := (row * 100 + col * 10 + channel) mod 256;
        return std_logic_vector(to_signed(temp - 128, 8));  -- Convert to signed Q1.6
    end function;

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: calc_index
        generic map (
            NODES_IN       => NODES_IN,
            INPUT_CHANNELS => INPUT_CHANNELS,
            INPUT_SIZE     => INPUT_SIZE
        )
        port map (
            clk     => clk,
            rst     => rst,
            enable  => enable,
            
            req_row     => req_row,
            req_col     => req_col,
            req_valid   => req_valid,
            
            pool_pixel_data  => pool_pixel_data,
            pool_pixel_valid => pool_pixel_valid,
            pool_pixel_ready => pool_pixel_ready,
            
            fc_pixel_out    => fc_pixel_out,
            fc_pixel_valid  => fc_pixel_valid,
            fc_pixel_ready  => fc_pixel_ready,
            
            curr_index  => curr_index,
            done        => done
        );

    -- Clock process
    clk_process: process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- Continuous pixel data supply (simulates max pooling layer response)
    pixel_supply: process(clk)
    begin
        if rising_edge(clk) then
            -- Respond to requests with valid data on the next cycle
            if req_valid = '1' and pool_pixel_ready = '1' then
                pool_pixel_valid <= '1';
                -- Generate pixel data based on current requested position
                for ch in 0 to INPUT_CHANNELS-1 loop
                    pool_pixel_data(ch) <= gen_pixel_value(req_row, req_col, ch);
                end loop;
            else
                pool_pixel_valid <= '0';
            end if;
        end if;
    end process;

    -- Stimulus process
    stim_proc: process
        variable expected_row : integer;
        variable expected_col : integer;
        variable expected_channel : integer;
        variable expected_pixel : WORD_16;
    begin
        -- Initial reset
        report "========================================" severity note;
        report "Starting calc_index testbench" severity note;
        report "========================================" severity note;
        
        rst <= '1';
        enable <= '0';
        wait for CLK_PERIOD * 2;
        wait until rising_edge(clk);
        rst <= '0';
        wait for CLK_PERIOD;
        
        -- Test 1: Check initial state
        report "Test 1: Initial state check" severity note;
        wait until rising_edge(clk);
        assert done = '0' report "PASS: done initially low" severity note;
        assert req_valid = '0' report "PASS: req_valid initially low" severity note;
        assert fc_pixel_valid = '0' report "PASS: fc_pixel_valid initially low" severity note;
        
        -- Test 2: Enable and run through first few indices
        report "Test 2: Enable and verify first 20 indices" severity note;
        wait until rising_edge(clk);
        enable <= '1';
        
        for i in 0 to 19 loop
            wait until rising_edge(clk);
            
            -- Calculate expected values
            expected_channel := i mod INPUT_CHANNELS;
            expected_col := (i / INPUT_CHANNELS) mod INPUT_SIZE;
            expected_row := i / (INPUT_CHANNELS * INPUT_SIZE);
            
            -- Check outputs
            assert req_valid = '1' report "ERROR: req_valid should be high" severity error;
            assert fc_pixel_valid = '1' report "ERROR: fc_pixel_valid should be high" severity error;
            assert curr_index = i report "ERROR: curr_index = " & integer'image(curr_index) & ", expected " & integer'image(i) severity error;
            assert req_row = expected_row report "ERROR: req_row = " & integer'image(req_row) & ", expected " & integer'image(expected_row) severity error;
            assert req_col = expected_col report "ERROR: req_col = " & integer'image(req_col) & ", expected " & integer'image(expected_col) severity error;
            
            expected_pixel := gen_pixel_value(expected_row, expected_col, expected_channel);
            
            if fc_pixel_out = expected_pixel then
                report "PASS: Index " & integer'image(i) & " -> [" & integer'image(expected_row) & "," & integer'image(expected_col) & "," & integer'image(expected_channel) & "] = 0x" & to_hstring(unsigned(fc_pixel_out)) severity note;
            else
                report "ERROR: Index " & integer'image(i) & " pixel mismatch! Got 0x" & to_hstring(unsigned(fc_pixel_out)) & ", expected 0x" & to_hstring(unsigned(expected_pixel)) severity error;
            end if;
        end loop;
        
        -- Test 3: Check specific boundary indices
        report "Test 3: Verify key boundary indices" severity note;
        
        -- Let it run to index 15 (last channel of first position)
        wait until curr_index = 15;
        wait until rising_edge(clk);
        assert req_row = 0 and req_col = 0 report "ERROR: Index 15 should be [0,0,15]" severity error;
        report "PASS: Index 15 -> [0,0,15]" severity note;
        
        -- Index 16 (first channel of second position)
        wait until curr_index = 16;
        wait until rising_edge(clk);
        assert req_row = 0 and req_col = 1 report "ERROR: Index 16 should be [0,1,0]" severity error;
        report "PASS: Index 16 -> [0,1,0]" severity note;
        
        -- Index 80 (first of row 1)
        wait until curr_index = 80;
        wait until rising_edge(clk);
        assert req_row = 1 and req_col = 0 report "ERROR: Index 80 should be [1,0,0]" severity error;
        report "PASS: Index 80 -> [1,0,0]" severity note;
        
        -- Index 399 (last pixel)
        wait until curr_index = 399;
        wait until rising_edge(clk);
        assert req_row = 4 and req_col = 4 report "ERROR: Index 399 should be [4,4,15]" severity error;
        report "PASS: Index 399 -> [4,4,15]" severity note;
        
        -- Test 4: Check done signal and complete first full run
        report "Test 4: Complete first full run (0-399)" severity note;
        wait until done = '1';
        wait until rising_edge(clk);
        assert req_valid = '0' report "ERROR: req_valid should be low when done" severity error;
        assert fc_pixel_valid = '0' report "ERROR: fc_pixel_valid should be low when done" severity error;
        assert curr_index = 0 report "PASS: Index auto-reset to 0" severity note;
        report "PASS: First run complete, done signal asserted" severity note;
        
        -- Test 5: Second full run (0-399) - toggle enable to restart
        report "Test 5: Second full run (0-399)" severity note;
        
        -- Disable to clear done flag
        wait until rising_edge(clk);
        enable <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        assert done = '0' report "PASS: Done cleared when enable went low" severity note;
        assert curr_index = 0 report "PASS: Counter still at 0" severity note;
        
        -- Start second run
        wait until rising_edge(clk);
        enable <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert curr_index = 0 report "ERROR: Should start from index 0" severity error;
        assert req_row = 0 and req_col = 0 report "ERROR: Should restart from [0,0]" severity error;
        report "PASS: Second run started from index 0" severity note;
        
        -- Let second run complete
        wait until done = '1';
        wait until rising_edge(clk);
        report "PASS: Second run completed successfully" severity note;
        
        -- Test 6: Reset function mid-run (abort at index 200)
        report "Test 6: Test rst function - abort at index 200" severity note;
        wait until rising_edge(clk);
        enable <= '0';
        wait for CLK_PERIOD * 2;
        wait until rising_edge(clk);
        enable <= '1';
        
        -- Wait until index 200
        wait until curr_index = 200;
        wait until rising_edge(clk);
        report "PASS: Reached index 200, now applying reset" severity note;
        
        -- Apply reset to abort
        rst <= '1';
        wait for CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);
        
        assert curr_index = 0 report "PASS: Index reset to 0 by rst signal" severity note;
        assert done = '0' report "PASS: Done cleared by rst signal" severity note;
        
        -- Verify it can restart after rst
        wait until rising_edge(clk);
        assert req_row = 0 and req_col = 0 report "ERROR: Should restart from [0,0] after rst" severity error;
        report "PASS: Successfully restarted from index 0 after mid-run reset" severity note;
        
        -- End of test
        report "========================================" severity note;
        report "All tests completed successfully!" severity note;
        report "========================================" severity note;
        
        test_running <= false;
        wait;
    end process;

end Behavioral;
