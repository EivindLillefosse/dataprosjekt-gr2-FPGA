----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 19.09.2025
-- Design Name: 
-- Module Name: reLU_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: Testbench for ReLU activation function
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

entity reLU_tb is
end reLU_tb;

architecture Behavioral of reLU_tb is

    -- Component declaration
    component reLU is
        generic (
            IMAGE_SIZE : integer := 28;
            KERNEL_SIZE : integer := 3;
            STRIDE : integer := 1
        );
        Port ( 
            enable : in STD_LOGIC;
            done : out STD_LOGIC;
            clk : in STD_LOGIC;
            data : inout OUTPUT_ARRAY(0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                            0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1)
        );
    end component;

    -- Test signals
    signal clk_tb : STD_LOGIC := '0';
    signal enable_tb : STD_LOGIC := '0';
    signal done_tb : STD_LOGIC := '0';
    signal data_tb : OUTPUT_ARRAY(0 to ((28-3)/1)+1, 0 to ((28-3)/1)+1);
    
    -- Internal signals for driving the inout port
    signal data_drive : OUTPUT_ARRAY(0 to ((28-3)/1)+1, 0 to ((28-3)/1)+1);
    signal drive_enable : STD_LOGIC := '1';
    
    -- Clock period
    constant clk_period : time := 10 ns;
    
    -- Test constants
    constant TEST_SIZE : integer := ((28-3)/1); -- Should be 25 (26 total elements: 0 to 25)

begin

    -- Tri-state driver for inout port
    tri_state_driver: process(drive_enable, data_drive)
    begin
        if drive_enable = '1' then
            data_tb <= data_drive;
        else
            -- Set all elements to high impedance
            for row in 0 to ((28-3)/1)+1 loop
                for col in 0 to ((28-3)/1)+1 loop
                    data_tb(row, col) <= (others => 'Z');
                end loop;
            end loop;
        end if;
    end process;

    -- Instantiate the Unit Under Test (UUT)
    uut: reLU 
        generic map (
            IMAGE_SIZE => 28,
            KERNEL_SIZE => 3,
            STRIDE => 1
        )
        port map (
            enable => enable_tb,
            done => done_tb,
            clk => clk_tb,
            data => data_tb
        );

    -- Clock process
    clk_process: process
    begin
        clk_tb <= '0';
        wait for clk_period/2;
        clk_tb <= '1';
        wait for clk_period/2;
    end process;

    -- Test process
    test_process: process
    begin
        -- Initialize
        enable_tb <= '0';
        
        -- Initialize all data to zero first
        report "Test 0: Initializing all data to zero...";
        drive_enable <= '1'; -- Testbench drives the signal
        for row in 0 to TEST_SIZE+1 loop
            for col in 0 to TEST_SIZE+1 loop
                data_drive(row, col) <= "00000000";
            end loop;
        end loop;
        
        -- Wait for initialization to complete
        wait for clk_period * 3;
        
        -- Set test values AFTER initialization  
        report "Test 1: Setting input values...";
        data_drive(0, 0) <= "01111111"; -- 127 (positive)
        data_drive(0, 1) <= "10000000"; -- 128 (negative in signed)
        data_drive(1, 0) <= "00000001"; -- 1 (positive)  
        data_drive(1, 1) <= "11111111"; -- 255 (negative in signed)
        
        -- Wait for signal propagation
        wait for clk_period * 2;
        
        report "Test 2: Checking input values are set...";
        report "Before ReLU - data(0,0): " & integer'image(to_integer(unsigned(data_tb(0, 0))));
        report "Before ReLU - data(0,1): " & integer'image(to_integer(unsigned(data_tb(0, 1))));
        report "Before ReLU - data(1,0): " & integer'image(to_integer(unsigned(data_tb(1, 0))));
        report "Before ReLU - data(1,1): " & integer'image(to_integer(unsigned(data_tb(1, 1))));
        
        -- Test Case 1: Enable ReLU
        report "Test 3: Starting ReLU test...";
        drive_enable <= '0'; -- Let ReLU module take control
        enable_tb <= '1';
        
        -- Wait for processing to complete with longer timeout
        wait until rising_edge(done_tb) for 1000 ns;
        
        if done_tb = '1' then
            report "Test 4: ReLU processing completed";
        else
            report "ERROR: ReLU did not complete - done signal never went high";
        end if;
        
        wait for clk_period;
        
        report "After ReLU - data(0,0): " & integer'image(to_integer(unsigned(data_tb(0, 0))));
        report "After ReLU - data(0,1): " & integer'image(to_integer(unsigned(data_tb(0, 1))));
        
        enable_tb <= '0';
        drive_enable <= '1'; -- Take back control for next test
        wait for clk_period * 2;
        
        -- Test Case 2: Test with different values
        report "Testing with different values...";
        
        -- Set some specific test values
        data_drive(0, 0) <= "01111111"; -- 127 (positive)
        data_drive(0, 1) <= "10000000"; -- 128 (negative in signed)
        data_drive(1, 0) <= "00000001"; -- 1 (positive)
        data_drive(1, 1) <= "11111111"; -- 255 (negative in signed)
        
        wait for clk_period;
        drive_enable <= '0'; -- Let ReLU take control
        enable_tb <= '1';
        
        wait until rising_edge(done_tb);
        wait for clk_period;
        
        -- Check specific results
        assert data_tb(0, 0) = "01111111" report "ERROR: 127 should remain unchanged" severity error;
        assert data_tb(0, 1) = "00000000" report "ERROR: 128 should become zero" severity error;
        assert data_tb(1, 0) = "00000001" report "ERROR: 1 should remain unchanged" severity error;
        assert data_tb(1, 1) = "00000000" report "ERROR: 255 should become zero" severity error;
        
        enable_tb <= '0';
        wait for clk_period * 2;
        
        report "ReLU testbench completed!";
        wait;
        
    end process;

end Behavioral;
