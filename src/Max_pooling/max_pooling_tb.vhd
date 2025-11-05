library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity max_pooling_tb is
end max_pooling_tb;

architecture sim of max_pooling_tb is
    -- Test parameters
    constant INPUT_SIZE     : integer := 8;   -- 8x8 input matrix
    constant OUTPUT_SIZE    : integer := 4;   -- 4x4 output (INPUT_SIZE/2)
    constant INPUT_CHANNELS : integer := 8;   -- Number of channels
    constant BLOCK_SIZE     : integer := 2;   -- 2x2 pooling
    constant CLK_PERIOD     : time := 10 ns;
    
    -- Test signals
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '0';
    
    -- Output request from downstream (testbench acts as downstream consumer)
    signal pixel_out_req_row   : integer := 0;
    signal pixel_out_req_col   : integer := 0;
    signal pixel_out_req_valid : std_logic := '0';
    signal pixel_out_req_ready : std_logic;
    
    -- Input request to upstream (testbench acts as upstream provider)
    signal pixel_in_req_row    : integer;
    signal pixel_in_req_col    : integer;
    signal pixel_in_req_valid  : std_logic;
    signal pixel_in_req_ready  : std_logic := '0';
    
    -- Input data from upstream
    signal pixel_in            : WORD_ARRAY(0 to INPUT_CHANNELS-1) := (others => (others => '0'));
    signal pixel_in_valid      : std_logic := '0';
    signal pixel_in_ready      : std_logic;
    
    -- Output data to downstream
    signal pixel_out           : WORD_ARRAY(0 to INPUT_CHANNELS-1);
    signal pixel_out_valid     : std_logic;
    signal pixel_out_ready     : std_logic := '0';
    
    -- Test data - 8x8 input matrix with known values (channel 0)
    type test_matrix_type is array (0 to INPUT_SIZE-1, 0 to INPUT_SIZE-1) of integer;
    constant TEST_MATRIX : test_matrix_type := (
        (10, 20, 30, 40, 50, 60, 70, 80),
        (15, 25, 35, 45, 55, 65, 75, 85),
        (11, 21, 31, 41, 51, 61, 71, 81),
        (16, 26, 36, 46, 56, 66, 76, 86),
        (12, 22, 32, 42, 52, 62, 72, 82),
        (17, 27, 37, 47, 57, 67, 77, 87),
        (13, 23, 33, 43, 53, 63, 73, 83),
        (18, 28, 38, 48, 58, 68, 78, 88)
    );
    
    -- Expected output matrix (4x4) - max of each 2x2 window
    type expected_matrix_type is array (0 to OUTPUT_SIZE-1, 0 to OUTPUT_SIZE-1) of integer;
    constant EXPECTED_OUTPUT : expected_matrix_type := (
        (25, 45, 65, 85),  -- max of (10,20,15,25), (30,40,35,45), etc.
        (26, 46, 66, 86),  -- max of (11,21,16,26), (31,41,36,46), etc.
        (27, 47, 67, 87),  -- max of (12,22,17,27), (32,42,37,47), etc.
        (28, 48, 68, 88)   -- max of (13,23,18,28), (33,43,38,48), etc.
    );
    
    signal test_done : boolean := false;

begin
    -- Clock generation
    clk_proc: process
    begin
        while not test_done loop
            clk <= '0'; 
            wait for CLK_PERIOD/2;
            clk <= '1'; 
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- DUT instantiation  
    dut: entity work.max_pooling
        generic map (
            INPUT_SIZE     => INPUT_SIZE,
            INPUT_CHANNELS => INPUT_CHANNELS,
            BLOCK_SIZE     => BLOCK_SIZE
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            pixel_out_req_row   => pixel_out_req_row,
            pixel_out_req_col   => pixel_out_req_col,
            pixel_out_req_valid => pixel_out_req_valid,
            pixel_out_req_ready => pixel_out_req_ready,
            pixel_in_req_row    => pixel_in_req_row,
            pixel_in_req_col    => pixel_in_req_col,
            pixel_in_req_valid  => pixel_in_req_valid,
            pixel_in_req_ready  => pixel_in_req_ready,
            pixel_in            => pixel_in,
            pixel_in_valid      => pixel_in_valid,
            pixel_in_ready      => pixel_in_ready,
            pixel_out           => pixel_out,
            pixel_out_valid     => pixel_out_valid,
            pixel_out_ready     => pixel_out_ready
        );

    -- Upstream provider process (simulates Conv layer providing input data)
    upstream_provider: process(clk)
        variable req_pending : std_logic := '0';
        variable pending_row : integer := 0;
        variable pending_col : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pixel_in_req_ready <= '0';
                pixel_in_valid <= '0';
                req_pending := '0';
            else
                -- Default
                pixel_in_req_ready <= '0';
                pixel_in_valid <= '0';
                
                -- If we have a pending request, provide the data
                if req_pending = '1' then
                    -- Provide data from test matrix
                    for ch in 0 to INPUT_CHANNELS-1 loop
                        pixel_in(ch) <= std_logic_vector(to_signed(
                            TEST_MATRIX(pending_row, pending_col) + ch, 
                            WORD'length));
                    end loop;
                    pixel_in_valid <= '1';
                    req_pending := '0';
                end if;
                
                -- If pooling requests an input position, acknowledge and schedule data
                if pixel_in_req_valid = '1' and req_pending = '0' then
                    pixel_in_req_ready <= '1';  -- Acknowledge request
                    pending_row := pixel_in_req_row;
                    pending_col := pixel_in_req_col;
                    req_pending := '1';
                    
                    report "Upstream: Received request for position [" & 
                           integer'image(pixel_in_req_row) & "," & 
                           integer'image(pixel_in_req_col) & "]" severity note;
                end if;
            end if;
        end if;
    end process;

    -- Main test stimulus (acts as downstream consumer requesting outputs)
    stim_proc: process
        variable received_val : integer;
        variable expected_val : integer;
    begin
        -- Initial reset
        rst <= '1';
        pixel_out_req_valid <= '0';
        pixel_out_ready <= '0';
        wait for 5*CLK_PERIOD;
        
        rst <= '0';
        wait for 2*CLK_PERIOD;
        
        report "=== Starting Max Pooling Test (Request/Response Protocol) ===" severity note;
        report "Requesting 4x4 output from 8x8 input" severity note;
        
        -- Request all 16 output positions (4x4 grid)
        for out_row in 0 to OUTPUT_SIZE-1 loop
            for out_col in 0 to OUTPUT_SIZE-1 loop
                report "Requesting output position [" & integer'image(out_row) & 
                       "," & integer'image(out_col) & "]" severity note;
                
                -- Send request
                pixel_out_req_row <= out_row;
                pixel_out_req_col <= out_col;
                pixel_out_req_valid <= '1';
                
                wait until rising_edge(clk) and pixel_out_req_ready = '1';
                pixel_out_req_valid <= '0';
                wait for CLK_PERIOD;
                
                -- Wait for output to be ready
                wait until rising_edge(clk) and pixel_out_valid = '1';
                
                -- Accept the output
                pixel_out_ready <= '1';
                
                -- Verify the result (check channel 0)
                received_val := to_integer(signed(pixel_out(0)));
                expected_val := EXPECTED_OUTPUT(out_row, out_col);
                
                if received_val = expected_val then
                    report "PASS: Output[" & integer'image(out_row) & "," & 
                           integer'image(out_col) & "] = " & integer'image(received_val) 
                           severity note;
                else
                    report "FAIL: Output[" & integer'image(out_row) & "," & 
                           integer'image(out_col) & "], expected " & 
                           integer'image(expected_val) & " but got " & 
                           integer'image(received_val) severity error;
                end if;
                
                wait for CLK_PERIOD;
                pixel_out_ready <= '0';
                wait for CLK_PERIOD;
            end loop;
        end loop;
        
        report "=== Max Pooling Test Complete ===" severity note;
        
        wait for 10*CLK_PERIOD;
        test_done <= true;
        wait;
    end process;

end architecture sim;
