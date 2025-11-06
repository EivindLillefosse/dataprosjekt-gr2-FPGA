----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Martin Brekke Nilsen
-- 
-- Create Date: 11/03/2025
-- Design Name: 
-- Module Name: SPI_memory_controller_debug_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: Debug testbench with 4-pixel buffers to verify:
--              - All buffer transitions (A→B, A→C, B→A, B→C, C→A, C→B)
--              - Busy flag functionality
--              - last_written_to flag behavior
--              - Dynamic buffer switching when busy
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
use work.types_pkg.ALL;

entity SPI_memory_controller_debug_tb is
end SPI_memory_controller_debug_tb;

architecture Behavioral of SPI_memory_controller_debug_tb is
    -- Reduced size for debugging: 4 pixels per buffer instead of 784
    constant PIXELS_PER_BUFFER : integer := 9;
    constant TOTAL_TEST_PIXELS : integer := 40; -- Send 40 pixels (10 complete buffers)
    constant IMAGE_WIDTH : integer := 3; -- For 4 pixels: 2x2 grid for easy address calculation
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- DUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal data_in : std_logic_vector(7 downto 0) := (others => '0');
    signal data_in_valid : std_logic := '0';
    signal data_in_ready : std_logic;
    signal data_out : WORD;
    signal data_out_valid : std_logic := '0';
    signal data_out_ready : std_logic := '0';
    signal data_out_col : integer := 0;
    signal data_out_row : integer := 0;
    
    -- Test control signals
    signal test_done : boolean := false;
    signal pixels_sent : integer := 0;
    
    -- Component declaration
    component SPI_memory_controller is
        generic (
            BUFFER_SIZE : integer := 9;
            IMAGE_WIDTH : integer := 3
        );
        port (
            clk : in std_logic;
            rst : in std_logic;
            data_in : in std_logic_vector(7 downto 0);
            data_in_valid : in std_logic;
            data_in_ready : out std_logic;
            data_out : out WORD;
            data_out_valid : out std_logic;
            data_out_ready : in std_logic;
            data_out_col : in integer;
            data_out_row : in integer
        );
    end component;

begin
    -- Instantiate the DUT (Device Under Test) with debug buffer size
    DUT: SPI_memory_controller
        generic map (
            BUFFER_SIZE => PIXELS_PER_BUFFER,  -- Use 4 pixels for debug
            IMAGE_WIDTH => IMAGE_WIDTH          -- 2x2 grid
        )
        port map (
            clk => clk,
            rst => rst,
            data_in => data_in,
            data_in_valid => data_in_valid,
            data_in_ready => data_in_ready,
            data_out => data_out,
            data_out_valid => data_out_valid,
            data_out_ready => data_out_ready,
            data_out_col => data_out_col,
            data_out_row => data_out_row
        );
    
    -- Clock generation
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
    
    -- Input data provider with slow, continuously toggling valid
    input_provider: process
        variable pixel_value : integer := 0;
        variable current_buffer : integer := 0;
        variable pixel_in_buffer : integer := 0;
    begin
        -- Wait for reset to deassert
        wait until rst = '0';
        wait until rising_edge(clk);
        
        report "========================================";
        report "Starting SPI Memory Controller Debug Test";
        report "Buffer size: " & integer'image(PIXELS_PER_BUFFER) & " pixels";
        report "Total pixels to send: " & integer'image(TOTAL_TEST_PIXELS);
        report "Expected buffer fills: " & integer'image(TOTAL_TEST_PIXELS / PIXELS_PER_BUFFER);
        report "========================================";
        report "";
        
        -- Send test pixels - keep updating data_in throughout entire test
        while not test_done loop
            -- Calculate current position EVERY cycle
            current_buffer := pixels_sent / PIXELS_PER_BUFFER;
            pixel_in_buffer := pixels_sent mod PIXELS_PER_BUFFER;
            pixel_value := (current_buffer * 10) + pixel_in_buffer + 10;
            
            -- Update data EVERY cycle based on current pixels_sent
            data_in <= std_logic_vector(to_unsigned(pixel_value mod 256, 8));
            
            -- Only increment pixels_sent if we haven't reached the limit
            if pixels_sent < TOTAL_TEST_PIXELS then
                -- Check handshake BEFORE waiting for clock
                if data_in_valid = '1' and data_in_ready = '1' then
                    if pixel_in_buffer = 0 then
                        report "";
                        report "--- Starting Buffer " & integer'image(current_buffer) & 
                               " (Overall pixel " & integer'image(pixels_sent) & ") ---";
                    end if;
                    
                    report "  Pixel " & integer'image(pixels_sent) & 
                           ": value=" & integer'image(pixel_value) &
                           " [Buf " & integer'image(current_buffer) & 
                           ", pos " & integer'image(pixel_in_buffer) & "]";
                    
                    if pixel_in_buffer = PIXELS_PER_BUFFER - 1 then
                        report "--- Buffer " & integer'image(current_buffer) & " COMPLETE ---";
                        report "";
                    end if;
                    
                    pixels_sent <= pixels_sent + 1;
                end if;
            end if;
            
            wait until rising_edge(clk);
        end loop;
        
        -- All pixels sent
        report "";
        report "========================================";
        report "All " & integer'image(TOTAL_TEST_PIXELS) & " pixels sent successfully";
        report "========================================";
        
        wait;
    end process;
    
    -- Separate process to toggle data_in_valid every 6 cycles
    valid_toggler: process
        variable count : integer := 0;
    begin
        wait until rst = '0';
        data_in_valid <= '0';
        
        while not test_done loop
            wait until rising_edge(clk);
            count := count + 1;
            
            -- Toggle every 6 cycles
            if (count mod 6) = 0 then
                data_in_valid <= not data_in_valid;
            end if;
        end loop;
        
        wait;
    end process;
    
    -- Simple read process - just reads addresses throughout the test
    data_out_ready_control: process
        variable col, row : integer;
    begin
        wait until rst = '0';
        data_out_ready <= '0';
        data_out_col <= 0;
        data_out_row <= 0;
        
        -- EARLY READ TEST: Try to read before any buffer is complete
        wait for CLK_PERIOD * 20;
        report "";
        report "=== EARLY READ TEST: Attempting read before buffer complete ===";
        report "    (Should wait in WAIT_FOR_DATA state)";
        data_out_col <= 0;
        data_out_row <= 0;
        data_out_ready <= '1';
        wait for CLK_PERIOD * 30;  -- Hold ready high while waiting
        data_out_ready <= '0';
        report "=== Early read test complete ===";
        report "";
        
        -- Wait for first buffer to complete
        wait until pixels_sent >= PIXELS_PER_BUFFER;
        wait for CLK_PERIOD * 10;
        
        -- Just do 10 simple read sessions with faster address changes
        for read_session in 1 to 10 loop
            report "=== READ SESSION " & integer'image(read_session) & " ===";
            
            -- Read all 4 addresses in 2x2 grid
            for i in 0 to PIXELS_PER_BUFFER - 1 loop
                -- Convert linear address to col/row (2x2 grid)
                col := i / IMAGE_WIDTH;
                row := i mod IMAGE_WIDTH;
                
                data_out_col <= col;
                data_out_row <= row;
                wait for CLK_PERIOD * 2;  -- Reduced from 5 to 2
                
                data_out_ready <= '1';
                report "  READ col=" & integer'image(col) & " row=" & integer'image(row) & 
                       " (addr=" & integer'image(i) & ")";
                wait for CLK_PERIOD;
                
                data_out_ready <= '0';
                wait for CLK_PERIOD * 3;  -- Reduced from 10 to 3
            end loop;
            
            report "=== Session " & integer'image(read_session) & " complete ===";
            
            -- Wait before next read session
            wait for CLK_PERIOD * 10;  -- Reduced from 20 to 10
        end loop;
        
        report "=== ALL READS DONE (10 sessions, 40 total data_out_ready pulses) ===";
        
        wait;
    end process;
    
    -- Monitor handshake and data flow with enhanced reporting
    transaction_monitor: process(clk)
        variable buffer_fill_count : integer := 0;
        variable last_data_out_ready : std_logic := '0';
        variable transitions_seen : integer := 0;
        variable stalls_detected : integer := 0;
    begin
        if rising_edge(clk) and rst = '0' then
            -- Monitor successful data transfers (handshake completion)
            if data_in_valid = '1' and data_in_ready = '1' then
                buffer_fill_count := buffer_fill_count + 1;
                
                -- Detect buffer transitions (every PIXELS_PER_BUFFER pixels)
                if (buffer_fill_count mod PIXELS_PER_BUFFER) = 0 then
                    transitions_seen := transitions_seen + 1;
                    report "    => TRANSITION " & integer'image(transitions_seen) & 
                           ": Buffer complete at pixel " & integer'image(buffer_fill_count);
                end if;
            end if;
            
            -- Monitor data_out_ready transitions (indicates busy flag changes)
            if data_out_ready /= last_data_out_ready then
                if data_out_ready = '1' then
                    report "";
                    report "    >>> DATA_OUT_READY ASSERTED <<<";
                    report "        -> Last completed buffer becomes BUSY";
                    report "        -> Controller must skip to next available buffer";
                    report "";
                else
                    report "";
                    report "    >>> DATA_OUT_READY RELEASED <<<";
                    report "        -> All buffers become AVAILABLE";
                    report "        -> Normal rotation resumes";
                    report "";
                end if;
                last_data_out_ready := data_out_ready;
            end if;
            
            -- Monitor when controller is not ready (indicates transition or all buffers busy)
            if data_in_valid = '1' and data_in_ready = '0' then
                stalls_detected := stalls_detected + 1;
                if stalls_detected = 1 or (stalls_detected mod 5) = 0 then
                    report "    [STALL] detected (cycle " & integer'image(stalls_detected) & 
                           "): Transition or all buffers busy";
                end if;
            end if;
        end if;
    end process;
    
    -- Simple test control
    test_control: process
    begin
        rst <= '1';
        report "";
        report "============================================================";
        report "   SPI MEMORY CONTROLLER SIMPLE TESTBENCH                  ";
        report "   Testing triple-buffer with multiple reads               ";
        report "============================================================";
        report "";
        wait for CLK_PERIOD * 5;
        rst <= '0';
        report ">> Test starting...";
        report "";
        
        -- Wait for all pixels to be written
        wait until pixels_sent >= TOTAL_TEST_PIXELS;
        wait for CLK_PERIOD * 1000;
        
        report "";
        report "============================================================";
        report "   TEST COMPLETE                                            ";
        report "   Total pixels: " & integer'image(TOTAL_TEST_PIXELS);
        report "   Read sessions: 10 (40 total reads)";
        report "============================================================";
        report "";
        
        test_done <= true;
        wait;
    end process;

end Behavioral;
