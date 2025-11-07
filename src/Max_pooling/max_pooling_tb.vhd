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
        type provider_state_t is (PROV_IDLE, PROV_WAIT_ACK, PROV_WAIT_DATA, PROV_SEND_DATA);
        variable state        : provider_state_t := PROV_IDLE;
        variable pending_row  : integer := 0;
        variable pending_col  : integer := 0;
        variable ack_delay    : integer range 0 to 2 := 0;
        variable data_delay   : integer range 0 to 2 := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pixel_in_req_ready <= '0';
                pixel_in_valid     <= '0';
                state              := PROV_IDLE;
                ack_delay          := 0;
                data_delay         := 0;
            else
                pixel_in_req_ready <= '0';
                pixel_in_valid     <= '0';

                case state is
                    when PROV_IDLE =>
                        if pixel_in_req_valid = '1' then
                            pending_row := pixel_in_req_row;
                            pending_col := pixel_in_req_col;
                            ack_delay   := (pending_row + pending_col) mod 2;
                            data_delay  := (pending_row + pending_col + 1) mod 2;
                            state       := PROV_WAIT_ACK;

                            report "Upstream: Received request for position [" &
                                   integer'image(pending_row) & "," &
                                   integer'image(pending_col) & "]" severity note;
                        end if;

                    when PROV_WAIT_ACK =>
                        if ack_delay = 0 then
                            pixel_in_req_ready <= '1';
                            state              := PROV_WAIT_DATA;
                        else
                            ack_delay := ack_delay - 1;
                        end if;

                    when PROV_WAIT_DATA =>
                        if data_delay = 0 then
                            state := PROV_SEND_DATA;
                        else
                            data_delay := data_delay - 1;
                        end if;

                    when PROV_SEND_DATA =>
                        for ch in 0 to INPUT_CHANNELS-1 loop
                            pixel_in(ch) <= std_logic_vector(to_signed(
                                TEST_MATRIX(pending_row, pending_col) + ch,
                                WORD'length));
                        end loop;
                        pixel_in_valid <= '1';
                        state          := PROV_IDLE;
                end case;
            end if;
        end if;
    end process;

    -- Main test stimulus (acts as downstream consumer requesting outputs)
    stim_proc: process
        variable test_pass    : boolean := true;
        variable tmp_result   : WORD_ARRAY(0 to INPUT_CHANNELS-1);
        variable baseline     : WORD_ARRAY(0 to INPUT_CHANNELS-1);

        procedure execute_request(
            constant out_row      : integer;
            constant out_col      : integer;
            constant hold_cycles  : integer;
            constant tag          : string;
            variable captured     : out WORD_ARRAY(0 to INPUT_CHANNELS-1);
            variable local_status : inout boolean) is
            variable first_capture : WORD_ARRAY(0 to INPUT_CHANNELS-1);
            variable received_val  : integer;
            variable expected_val  : integer;
        begin
            report tag & ": Requesting output position [" &
                   integer'image(out_row) & "," &
                   integer'image(out_col) & "]" severity note;

            pixel_out_req_row   <= out_row;
            pixel_out_req_col   <= out_col;
            pixel_out_req_valid <= '1';

            wait until rising_edge(clk) and pixel_out_req_ready = '1';
            pixel_out_req_valid <= '0';

            wait until rising_edge(clk);
            while pixel_out_valid = '0' loop
                wait until rising_edge(clk);
            end loop;

            first_capture := pixel_out;

            for delay in 1 to hold_cycles loop
                wait until rising_edge(clk);
                if pixel_out_valid /= '1' then
                    report tag & ": output_valid dropped before READY handshake" severity error;
                    local_status := false;
                end if;
                for ch in 0 to INPUT_CHANNELS-1 loop
                    if pixel_out(ch) /= first_capture(ch) then
                        report tag & ": Output changed while READY='0' at channel " &
                               integer'image(ch) severity error;
                        local_status := false;
                    end if;
                end loop;
            end loop;

            pixel_out_ready <= '1';
            wait until rising_edge(clk);
            if pixel_out_valid /= '1' then
                report tag & ": output_valid was not asserted during READY handshake" severity error;
                local_status := false;
            end if;
            pixel_out_ready <= '0';

            captured := first_capture;

            for ch in 0 to INPUT_CHANNELS-1 loop
                received_val := to_integer(signed(first_capture(ch)));
                expected_val := EXPECTED_OUTPUT(out_row, out_col) + ch;

                if received_val /= expected_val then
                    report tag & ": channel " & integer'image(ch) &
                           " expected " & integer'image(expected_val) &
                           " but got " & integer'image(received_val) severity error;
                    local_status := false;
                else
                    report tag & ": channel " & integer'image(ch) &
                           " = " & integer'image(received_val) severity note;
                end if;
            end loop;

            wait until rising_edge(clk);
            if pixel_out_valid = '1' then
                report tag & ": output_valid stuck high after READY handshake" severity error;
                local_status := false;
            end if;
        end procedure;
    begin
        rst <= '1';
        pixel_out_req_valid <= '0';
        pixel_out_ready     <= '0';
        wait for 5*CLK_PERIOD;

        rst <= '0';
        wait for 2*CLK_PERIOD;

        report "=== Starting Max Pooling Test (Robust Request/Response Protocol) ===" severity note;
        report "Requesting 4x4 output from 8x8 input" severity note;

        report "=== Test 1: Sweep all positions with varied READY latency ===" severity note;
        for out_row in 0 to OUTPUT_SIZE-1 loop
            for out_col in 0 to OUTPUT_SIZE-1 loop
                execute_request(out_row, out_col, (out_row + out_col) mod 3, "Test1", tmp_result, test_pass);
            end loop;
        end loop;

        report "=== Test 2: Determinism test - repeated requests for [0,0] ===" severity note;
        execute_request(0, 0, 2, "Test2_initial", baseline, test_pass);
        for repeat in 2 to 5 loop
            execute_request(0, 0, repeat mod 3, "Test2_repeat", tmp_result, test_pass);
            for ch in 0 to INPUT_CHANNELS-1 loop
                if tmp_result(ch) /= baseline(ch) then
                    report "Determinism failure: repeat #" & integer'image(repeat) &
                           " channel " & integer'image(ch) &
                           " changed from " & integer'image(to_integer(signed(baseline(ch)))) &
                           " to " & integer'image(to_integer(signed(tmp_result(ch)))) severity error;
                    test_pass := false;
                else
                    report "Determinism ok: repeat #" & integer'image(repeat) &
                           " channel " & integer'image(ch) &
                           " remains " & integer'image(to_integer(signed(tmp_result(ch)))) severity note;
                end if;
            end loop;
        end loop;

        report "=== Test 3: Interleaved positions to ensure state reset ===" severity note;
        execute_request(0, 0, 1, "Test3_phaseA", tmp_result, test_pass);
        execute_request(1, 1, 2, "Test3_phaseB", tmp_result, test_pass);
        execute_request(0, 0, 0, "Test3_phaseC", tmp_result, test_pass);

        if test_pass then
            report "=== ALL TESTS PASSED ===" severity note;
        else
            report "=== SOME TESTS FAILED ===" severity error;
        end if;

        report "=== Max Pooling Test Complete ===" severity note;

        wait for 10*CLK_PERIOD;
        test_done <= true;
        wait;
    end process;

end architecture sim;
