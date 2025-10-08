library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity max_pooling_tb is
end max_pooling_tb;

architecture sim of max_pooling_tb is
    -- Test parameters
    constant INPUT_WIDTH  : integer := 8;   -- 8x8 input matrix
    constant INPUT_HEIGHT : integer := 8;
    constant PIXEL_WIDTH  : integer := 16;  -- 16-bit pixels
    constant CLK_PERIOD   : time := 10 ns;
    
    -- Test signals
    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal start       : std_logic := '0';
    signal pixel_valid : std_logic := '0';
    signal pixel_in    : std_logic_vector(PIXEL_WIDTH-1 downto 0) := (others => '0');
    
    signal pixel_out   : std_logic_vector(PIXEL_WIDTH-1 downto 0);
    signal pixel_ready : std_logic;
    signal frame_done  : std_logic;
    
    -- Test data - 8x8 input matrix with known values
    type test_matrix_type is array (0 to INPUT_HEIGHT-1, 0 to INPUT_WIDTH-1) of integer;
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
    type expected_matrix_type is array (0 to 3, 0 to 3) of integer;
    constant EXPECTED_OUTPUT : expected_matrix_type := (
        (25, 45, 65, 85),  -- max of (10,20,15,25), (30,40,35,45), etc.
        (26, 46, 66, 86),  -- max of (11,21,16,26), (31,41,36,46), etc.
        (27, 47, 67, 87),  -- max of (12,22,17,27), (32,42,37,47), etc.
        (28, 48, 68, 88)   -- max of (13,23,18,28), (33,43,38,48), etc.
    );
    
    -- Output collection
    type output_array_type is array (0 to 15) of integer; -- 4x4 = 16 outputs
    signal received_outputs : output_array_type := (others => 0);
    signal output_count : integer := 0;

begin
    -- Clock generation
    clk_proc: process
    begin
        while true loop
            clk <= '0'; 
            wait for CLK_PERIOD/2;
            clk <= '1'; 
            wait for CLK_PERIOD/2;
        end loop;
    end process;

    -- DUT instantiation  
    dut: entity work.max_pooling
        generic map (
            INPUT_WIDTH  => INPUT_WIDTH,
            INPUT_HEIGHT => INPUT_HEIGHT,
            PIXEL_WIDTH  => PIXEL_WIDTH
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start       => start,
            pixel_valid => pixel_valid,
            pixel_in    => pixel_in,
            pixel_out   => pixel_out,
            pixel_ready => pixel_ready,
            frame_done  => frame_done
        );

    -- Output monitor process
    output_monitor: process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                output_count <= 0;
                received_outputs <= (others => 0);
            elsif pixel_ready = '1' then
                assert false report "Output pixel received" severity note;
                received_outputs(output_count) <= to_integer(unsigned(pixel_out));
                output_count <= output_count + 1;
            end if;
        end if;
    end process;

    -- Main stimulus process
    stim_proc: process
        variable expected_row : integer;
        variable expected_col : integer;
        variable expected_val : integer;
        variable received_val : integer;
    begin
        -- Initial reset
        rst_n <= '0';
        start <= '0';
        pixel_valid <= '0';
        pixel_in <= (others => '0');
        wait for 5*CLK_PERIOD;
        
        rst_n <= '1';
        wait for 2*CLK_PERIOD;
        
        assert false report "=== Starting Max Pooling Test ===" severity note;
        assert false report "Sending 8x8 matrix, expecting 4x4 output" severity note;
        
        -- Start the frame
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        wait for CLK_PERIOD;
        
        -- Send the 8x8 matrix row by row (64 pixels total)
        for row in 0 to INPUT_HEIGHT-1 loop
            for col in 0 to INPUT_WIDTH-1 loop
                -- Send pixel
                pixel_in <= std_logic_vector(to_unsigned(TEST_MATRIX(row, col), PIXEL_WIDTH));
                pixel_valid <= '1';
                wait for CLK_PERIOD;
                pixel_valid <= '0';
                
                -- Small gap between pixels
                wait for CLK_PERIOD;
            end loop;
            
            -- Gap between rows
            wait for 2*CLK_PERIOD;
        end loop;
        
        -- Wait for processing to complete
        wait until frame_done = '1';
        wait for 5*CLK_PERIOD;
        
        -- Verify results
        assert false report "=== Verifying Results ===" severity note;
        
        for i in 0 to 15 loop
            expected_row := i / 4;
            expected_col := i mod 4;
            expected_val := EXPECTED_OUTPUT(expected_row, expected_col);
            received_val := received_outputs(i);
            
            if received_val = expected_val then
                assert false report "PASS: Output " & integer'image(i) & 
                       " = " & integer'image(received_val) severity note;
            else
                assert false report "Error: At " & integer'image(now / 1 ns) & " ns: Output " & integer'image(i) & 
                       ", expected " & integer'image(expected_val) & 
                       " but got " & integer'image(received_val) severity error;
            end if;
        end loop;
        
        -- Test reset during operation
        assert false report "=== Testing Reset During Operation ===" severity note;
        
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        
        -- Send a few pixels then reset
        for i in 0 to 10 loop
            pixel_in <= std_logic_vector(to_unsigned(100 + i, PIXEL_WIDTH));
            pixel_valid <= '1';
            wait for CLK_PERIOD;
            pixel_valid <= '0';
            wait for CLK_PERIOD;
        end loop;
        
        -- Apply reset
        rst_n <= '0';
        wait for 3*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;
        
        assert false report "=== Max Pooling Test Complete ===" severity note;
        wait;
    end process;

end architecture sim;
