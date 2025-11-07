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
    signal col_row_req_ready : std_logic;
    signal col_row_req_valid : std_logic := '0';
    
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
            data_out_row : in integer;
            col_row_req_ready : out std_logic;
            col_row_req_valid : in std_logic
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
            data_out_row => data_out_row,
            col_row_req_ready => col_row_req_ready,
            col_row_req_valid => col_row_req_valid
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
    
    -- Proper read process following RTL handshake protocol:
    -- 1. Set col/row and assert col_row_req_valid
    -- 2. Wait for FSM to reach WAIT_BRAM state
    -- 3. Assert data_out_ready to load data
    -- 4. Wait for data_out_valid
    data_out_ready_control: process
        variable col, row : integer;
    begin
        wait until rst = '0';
        data_out_ready <= '0';
        col_row_req_valid <= '0';
        data_out_col <= 0;
        data_out_row <= 0;
        
        -- Wait for first buffer to complete
        wait until pixels_sent >= PIXELS_PER_BUFFER;
        wait until col_row_req_ready = '1';
        wait for CLK_PERIOD * 5;
        
        report "";
        report "=== col_row_req_ready is HIGH - buffers available ===";
        report "";
        
        -- Perform 15 individual read transactions (each toggles col_row_req_valid)
        for read_transaction in 1 to 15 loop
            -- Cycle through all possible addresses (0-8) repeatedly
            col := (read_transaction - 1) mod IMAGE_WIDTH;
            row := (read_transaction - 1) / IMAGE_WIDTH;
            
            report "";
            report "========================================";
            report "READ TRANSACTION #" & integer'image(read_transaction) & " of 15";
            report "========================================";
            
            -- STEP 1: Ensure signals are low initially (clean state)
            col_row_req_valid <= '0';
            data_out_ready <= '0';
            report "  STEP 0: Both signals LOW (clean state)";
            wait for CLK_PERIOD * 3;
            
            -- STEP 2: Present col/row address and assert col_row_req_valid
            data_out_col <= col;
            data_out_row <= row;
            col_row_req_valid <= '1';
            report "  STEP 1: col=" & integer'image(col) & " row=" & integer'image(row) & 
                   " (linear addr=" & integer'image((read_transaction - 1) mod PIXELS_PER_BUFFER) & ")";
            report "          >>> col_row_req_valid = '1' (ASSERTED) <<<";
            wait for CLK_PERIOD * 2;
            
            -- Wait for FSM to process (READ_IDLE -> READ_ADDR -> WAIT_ADDR_SETTLE -> WAIT_BRAM)
            report "  STEP 2: Waiting for FSM to reach WAIT_BRAM...";
            wait for CLK_PERIOD * 4;
            
            -- STEP 3: Now assert data_out_ready to trigger data load
            data_out_ready <= '1';
            report "  STEP 3: >>> data_out_ready = '1' (trigger load) <<<";
            
            -- Wait for data_out_valid to assert
            wait until data_out_valid = '1' for CLK_PERIOD * 10;
            if data_out_valid = '1' then
                report "  STEP 4: data_out_valid = '1', data = 0x" & 
                       integer'image(to_integer(unsigned(data_out)));
            else
                report "  ERROR: Timeout waiting for data_out_valid!";
            end if;
            wait for CLK_PERIOD;
            
            -- STEP 4: Deassert both signals
            data_out_ready <= '0';
            col_row_req_valid <= '0';
            report "  STEP 5: >>> col_row_req_valid = '0' (DEASSERTED) <<<";
            report "          >>> data_out_ready = '0' (DEASSERTED) <<<";
            report "          Transaction complete!";
            report "";
            
            -- Longer gap between transactions to make toggles visible
            wait for CLK_PERIOD * 10;
        end loop;
        
        report "";
        report "============================================";
        report "ALL READ TRANSACTIONS COMPLETE";
        report "Total reads: 15 (col_row_req_valid toggled 15 times)";
        report "============================================";
        report "";
        
        wait;
    end process;
    
    -- Monitor handshake and data flow
    transaction_monitor: process(clk)
        variable write_count : integer := 0;
        variable read_count : integer := 0;
        variable last_col_row_req_ready : std_logic := '0';
    begin
        if rising_edge(clk) and rst = '0' then
            -- Monitor successful writes
            if data_in_valid = '1' and data_in_ready = '1' then
                write_count := write_count + 1;
                
                if (write_count mod PIXELS_PER_BUFFER) = 0 then
                    report "    => WRITE: Buffer complete at pixel " & integer'image(write_count);
                end if;
            end if;
            
            -- Monitor successful reads
            if data_out_valid = '1' then
                read_count := read_count + 1;
                report "    <= READ #" & integer'image(read_count) & 
                       ": data=" & integer'image(to_integer(unsigned(data_out)));
            end if;
            
            -- Monitor col_row_req_ready transitions
            if col_row_req_ready /= last_col_row_req_ready then
                if col_row_req_ready = '1' then
                    report "";
                    report "    >>> col_row_req_ready ASSERTED <<<";
                    report "        -> Buffer(s) ready for reading";
                    report "";
                else
                    report "";
                    report "    >>> col_row_req_ready DEASSERTED <<<";
                    report "        -> No complete buffers available";
                    report "";
                end if;
                last_col_row_req_ready := col_row_req_ready;
            end if;
        end if;
    end process;
    
    -- Test control
    test_control: process
    begin
        rst <= '1';
        report "";
        report "============================================================";
        report "   SPI MEMORY CONTROLLER TESTBENCH                          ";
        report "   Testing proper read/write handshake protocol             ";
        report "============================================================";
        report "";
        report "Protocol (each transaction toggles col_row_req_valid):";
        report "  1. Deassert col_row_req_valid (ensure clean state)";
        report "  2. Set col/row and assert col_row_req_valid";
        report "  3. Wait ~3 cycles for FSM (READ_ADDR -> WAIT_BRAM)";
        report "  4. Assert data_out_ready to load data";
        report "  5. Wait for data_out_valid = '1'";
        report "  6. Deassert both col_row_req_valid and data_out_ready";
        report "";
        wait for CLK_PERIOD * 5;
        rst <= '0';
        report ">> Test starting...";
        report "";
        
        -- Wait for all pixels to be written and reads to complete
        wait until pixels_sent >= TOTAL_TEST_PIXELS;
        wait for CLK_PERIOD * 2000;
        
        report "";
        report "============================================================";
        report "   TEST COMPLETE                                            ";
        report "   Total pixels written: " & integer'image(TOTAL_TEST_PIXELS);
        report "   Read transactions: 15 (col_row_req_valid toggled 15x)";
        report "   Each transaction: DEASSERT -> ASSERT -> DEASSERT";
        report "============================================================";
        report "";
        
        test_done <= true;
        wait;
    end process;

end Behavioral;
