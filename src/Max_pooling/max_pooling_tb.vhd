library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity max_pooling_tb is
end max_pooling_tb;

architecture sim of max_pooling_tb is
    -- Test parameters
    constant INPUT_WIDTH  : integer := 8;   -- 8x8 input matrix
    constant INPUT_HEIGHT : integer := 8;
    constant INPUT_CHANNELS : integer := 8; -- Number of channels
    constant CLK_PERIOD   : time := 10 ns;
    
    -- Test signals
    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal pixel_in_valid : std_logic := '0';
    signal pixel_in    : WORD_ARRAY(0 to INPUT_CHANNELS-1) := (others => (others => '0'));
    signal pixel_out   : WORD_ARRAY(0 to INPUT_CHANNELS-1);
    signal pixel_out_ready : std_logic;
    signal pixel_in_ready : std_logic;
    signal pixel_in_row : integer := 0;
    signal pixel_in_col : integer := 0;
    
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
            INPUT_SIZE     => INPUT_WIDTH,
            INPUT_CHANNELS => INPUT_CHANNELS,
            BLOCK_SIZE     => 2
        )
        port map (
            clk         => clk,
            rst_n           => rst_n,
            pixel_in_valid  => pixel_in_valid,
            pixel_in_ready  => pixel_in_ready,
            pixel_in        => pixel_in,
            pixel_in_row    => pixel_in_row,
            pixel_in_col    => pixel_in_col,
            pixel_out       => pixel_out,
            pixel_out_ready => pixel_out_ready
        );

    -- Output monitor process (monitors channel 0 for simplicity)
    output_monitor: process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                output_count <= 0;
                received_outputs <= (others => 0);
            elsif pixel_out_ready = '1' then
                assert false report "Output pixel received" severity note;
                received_outputs(output_count) <= to_integer(signed(pixel_out(0)));
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
        variable br : integer;
        variable bc : integer;
    begin
        -- Initial reset
        rst_n <= '0';
        pixel_in_valid <= '0';
        pixel_in <= (others => (others => '0'));
        wait for 5*CLK_PERIOD;
        
        rst_n <= '1';
        wait for 2*CLK_PERIOD;
        
        assert false report "=== Starting Max Pooling Test ===" severity note;
        assert false report "Sending 8x8 matrix, expecting 4x4 output" severity note;
        
    -- Send the 8x8 matrix in 2x2 block order: (r,c),(r,c+1),(r+1,c),(r+1,c+1)
    -- Use stepping by 2 using while loops (works for even INPUT_WIDTH/HEIGHT)

    br := 0;
        while br < INPUT_HEIGHT loop
            bc := 0;
            while bc < INPUT_WIDTH loop
                -- (br, bc)
                pixel_in_row <= br;
                pixel_in_col <= bc;
                for ch in 0 to INPUT_CHANNELS-1 loop
                    -- Give each channel a distinct value: base + channel index
                    pixel_in(ch) <= std_logic_vector(to_signed(TEST_MATRIX(br, bc) + ch, WORD'length));
                end loop;
                pixel_in_valid <= '1';
                wait for CLK_PERIOD;
                pixel_in_valid <= '0';
                wait for CLK_PERIOD;

                -- (br, bc+1)
                pixel_in_row <= br;
                pixel_in_col <= bc + 1;
                for ch in 0 to INPUT_CHANNELS-1 loop
                    pixel_in(ch) <= std_logic_vector(to_signed(TEST_MATRIX(br, bc+1) + ch, WORD'length));
                end loop;
                pixel_in_valid <= '1';
                wait for CLK_PERIOD;
                pixel_in_valid <= '0';
                wait for CLK_PERIOD;

                -- (br+1, bc)
                pixel_in_row <= br + 1;
                pixel_in_col <= bc;
                for ch in 0 to INPUT_CHANNELS-1 loop
                    pixel_in(ch) <= std_logic_vector(to_signed(TEST_MATRIX(br+1, bc) + ch, WORD'length));
                end loop;
                pixel_in_valid <= '1';
                wait for CLK_PERIOD;
                pixel_in_valid <= '0';
                wait for CLK_PERIOD;

                -- (br+1, bc+1)
                pixel_in_row <= br + 1;
                pixel_in_col <= bc + 1;
                for ch in 0 to INPUT_CHANNELS-1 loop
                    pixel_in(ch) <= std_logic_vector(to_signed(TEST_MATRIX(br+1, bc+1) + ch, WORD'length));
                end loop;
                pixel_in_valid <= '1';
                wait for CLK_PERIOD;
                pixel_in_valid <= '0';
                wait for CLK_PERIOD;

                -- small gap after finishing one 2x2 block
                wait for CLK_PERIOD;

                bc := bc + 2;
            end loop;
            -- gap after finishing a row of blocks
            wait for 2*CLK_PERIOD;
            br := br + 2;
        end loop;

        -- Wait until all 16 outputs have been produced
        wait until output_count = 16;
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

        -- Start sending a new short frame (a few pixels)
        for i in 0 to 10 loop
            pixel_in_row <= i / INPUT_WIDTH;
            pixel_in_col <= i mod INPUT_WIDTH;
            for ch in 0 to INPUT_CHANNELS-1 loop
                pixel_in(ch) <= std_logic_vector(to_signed(100 + i + ch, WORD'length));
            end loop;
            pixel_in_valid <= '1';
            wait for CLK_PERIOD;
            pixel_in_valid <= '0';
            wait for CLK_PERIOD;
        end loop;

        -- Apply reset in the middle of operation
        rst_n <= '0';
        wait for 3*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;
        
        assert false report "=== Max Pooling Test Complete ===" severity note;
        wait;
    end process;

end architecture sim;
