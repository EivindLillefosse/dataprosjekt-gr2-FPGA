----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 01.11.2025
-- Design Name: CNN Top-Level Testbench
-- Module Name: cnn_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: Testbench for CNN top-level module
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

-- Required for file I/O operations
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
-- Optional: VHDL-2008 simulator control (std.env). Some simulators support this to stop/finish simulation.
use std.env.all;

entity cnn_tb is
end cnn_tb;

architecture Behavioral of cnn_tb is
    -- Test parameters (matching CNN top-level)
    constant IMAGE_SIZE : integer := 28;
    
    -- Final output will be from CONV_2 with 16 filters (for now)
    constant FINAL_NUM_FILTERS : integer := 16;
    constant FC1_NODES_OUT : integer := 64;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk : STD_LOGIC := '0';
    signal rst : STD_LOGIC := '0';
    
    -- Request/response signals for output
    signal output_req_row   : integer := 0;
    signal output_req_col   : integer := 0;
    signal output_req_valid : std_logic := '0';
    signal output_req_ready : std_logic;
    
    -- Request/response signals for input
    signal input_req_row    : integer;
    signal input_req_col    : integer;
    signal input_req_valid  : std_logic;
    signal input_req_ready  : std_logic := '0';
    
    -- Data signals
    signal input_pixel : WORD_ARRAY_16(0 to 0) := (others => (others => '0'));
    signal input_valid : std_logic := '0';
    signal input_ready : std_logic;
    
    signal output_pixel : WORD_ARRAY_16(0 to FINAL_NUM_FILTERS-1);
    signal output_valid : std_logic;
    signal output_ready : std_logic := '0';
    signal output_guess : WORD;
    
    -- Control signal for Pool2 mux
    signal use_fc_path  : std_logic := '0';  -- '0' = testbench controls, '1' = calc_index controls
    
    -- FC1 output signals (for monitoring)
    signal fc1_output_data  : WORD_ARRAY(0 to FC1_NODES_OUT-1);
    signal fc1_output_valid : std_logic;
    signal fc1_output_ready : std_logic := '0';
    
    -- DEBUG: Intermediate layer signals
    signal debug_conv1_pixel : WORD_ARRAY_16(0 to 7);  -- 8 filters
    signal debug_conv1_valid : std_logic;
    signal debug_conv1_ready : std_logic := '0';
    signal debug_conv1_row   : natural := 0;
    signal debug_conv1_col   : natural := 0;
    
    signal debug_pool1_pixel : WORD_ARRAY_16(0 to 7);  -- 8 filters
    signal debug_pool1_valid : std_logic;
    signal debug_pool1_ready : std_logic := '0';
    signal debug_pool1_row   : natural := 0;
    signal debug_pool1_col   : natural := 0;
    
    signal debug_conv2_pixel : WORD_ARRAY_16(0 to 15); -- 16 filters
    signal debug_conv2_valid : std_logic;
    signal debug_conv2_ready : std_logic := '0';
    signal debug_conv2_row   : natural := 0;
    signal debug_conv2_col   : natural := 0;
    
    signal debug_pool2_pixel : WORD_ARRAY(0 to 15); -- 16 filters
    signal debug_pool2_valid : std_logic;
    signal debug_pool2_ready : std_logic := '0';
    signal debug_pool2_row   : natural := 0;
    signal debug_pool2_col   : natural := 0;
    
    -- DEBUG: calc_index signals
    signal debug_calc_index  : integer range 0 to 399;
    signal debug_calc_pixel  : WORD;
    signal debug_calc_valid  : std_logic;
    signal debug_calc_done   : std_logic;
    
    -- Test image data (28x28 image)
    type test_image_type is array (0 to IMAGE_SIZE-1, 0 to IMAGE_SIZE-1) of integer;
    
    -- Function to generate 28x28 test image (same pattern as Python)
    function generate_test_image return test_image_type is
        variable temp_image : test_image_type;
    begin
        -- Generate the same pattern as Python: (row + col + 1) mod 256
        for row in 0 to IMAGE_SIZE-1 loop
            for col in 0 to IMAGE_SIZE-1 loop
                temp_image(row, col) := (row + col + 1) mod 256;
            end loop;
        end loop;
        return temp_image;
    end function;
    
    -- Use generated function (guaranteed to match Python)
    constant test_image : test_image_type := generate_test_image;
    
    -- Test control signals
    signal test_done : boolean := false;
    -- Verbosity control: set to true to enable detailed console reports
    constant VERBOSE_DETAIL : boolean := false;

begin
    -- Unit Under Test (UUT) - CNN Top-Level
    uut: entity work.cnn_top_debug
        generic map (
            IMAGE_SIZE => IMAGE_SIZE
        )
        port map (
            clk              => clk,
            rst              => rst,
            
            -- Output request interface
            output_req_row   => output_req_row,
            output_req_col   => output_req_col,
            output_req_valid => output_req_valid,
            output_req_ready => output_req_ready,
            
            -- Input request interface
            input_req_row    => input_req_row,
            input_req_col    => input_req_col,
            input_req_valid  => input_req_valid,
            input_req_ready  => input_req_ready,
            
            -- Data interfaces
            input_pixel      => input_pixel,
            input_valid      => input_valid,
            input_ready      => input_ready,
            
            output_pixel     => output_pixel,
            output_valid     => output_valid,
            output_ready     => output_ready,
            output_guess     => output_guess,
            
            -- Control Pool2 mux
            use_fc_path      => use_fc_path,
            
            -- FC1 outputs (new)
            fc1_output_data  => fc1_output_data,
            fc1_output_valid => fc1_output_valid,
            fc1_output_ready => fc1_output_ready,
            
            -- DEBUG: Intermediate layer outputs
            debug_conv1_pixel => debug_conv1_pixel,
            debug_conv1_valid => debug_conv1_valid,
            debug_conv1_ready => debug_conv1_ready,
            debug_conv1_row   => debug_conv1_row,
            debug_conv1_col   => debug_conv1_col,
            
            debug_pool1_pixel => debug_pool1_pixel,
            debug_pool1_valid => debug_pool1_valid,
            debug_pool1_ready => debug_pool1_ready,
            debug_pool1_row   => debug_pool1_row,
            debug_pool1_col   => debug_pool1_col,
            
            debug_conv2_pixel => debug_conv2_pixel,
            debug_conv2_valid => debug_conv2_valid,
            debug_conv2_ready => debug_conv2_ready,
            debug_conv2_row   => debug_conv2_row,
            debug_conv2_col   => debug_conv2_col,
            
            debug_pool2_pixel => debug_pool2_pixel,
            debug_pool2_valid => debug_pool2_valid,
            debug_pool2_ready => debug_pool2_ready,
            debug_pool2_row   => debug_pool2_row,
            debug_pool2_col   => debug_pool2_col,
            
            -- DEBUG: calc_index signals
            debug_calc_index  => debug_calc_index,
            debug_calc_pixel  => debug_calc_pixel,
            debug_calc_valid  => debug_calc_valid,
            debug_calc_done   => debug_calc_done
        );

    -- Clock process
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

    -- Input pixel provider process
    -- Responds to input position requests from the CNN
    input_provider: process(clk)
        variable req_pending : boolean := false;
        variable req_row_buf : integer := 0;
        variable req_col_buf : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                input_req_ready <= '0';
                input_valid <= '0';
                req_pending := false;
            else
                -- Default: not ready for new requests, no data valid
                input_req_ready <= '0';
                input_valid <= '0';
                
                -- Accept new position requests
                if input_req_valid = '1' and not req_pending then
                    input_req_ready <= '1';  -- Acknowledge request
                    req_row_buf := input_req_row;
                    req_col_buf := input_req_col;
                    req_pending := true;
                end if;
                
                -- Provide data for pending request
                if req_pending then
                          if req_row_buf >= 0 and req_row_buf < IMAGE_SIZE and 
                              req_col_buf >= 0 and req_col_buf < IMAGE_SIZE then
                                input_pixel(0) <= std_logic_vector(to_unsigned(test_image(req_row_buf, req_col_buf), 16));
                    else
                        -- Provide zero for out-of-bounds pixels (padding)
                        input_pixel(0) <= (others => '0');
                    end if;
                    input_valid <= '1';
                    
                    -- Wait for acknowledgment
                    if input_ready = '1' then
                        req_pending := false;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Monitor input requests (separate process for reporting)
    input_monitor: process(clk)
    begin
        if rising_edge(clk) then
                if input_req_valid = '1' and input_req_ready = '1' then
                    if VERBOSE_DETAIL then
                        if input_req_row >= 0 and input_req_row < IMAGE_SIZE and 
                           input_req_col >= 0 and input_req_col < IMAGE_SIZE then
                            report "Input requested [" & integer'image(input_req_row) & "," & integer'image(input_req_col) & "]";
                        else
                            report "Input requested (padding) [" & integer'image(input_req_row) & "," & integer'image(input_req_col) & "]";
                        end if;
                    end if;
                end if;

                if input_valid = '1' and input_ready = '1' then
                    if VERBOSE_DETAIL then
                        report "Input provided: " & integer'image(to_integer(unsigned(input_pixel(0))));
                    end if;
                end if;
        end if;
    end process;

    -- Output monitor process with FC1 output capture
    output_monitor: process(clk)
        file debug_file : text open write_mode is "cnn_intermediate_debug.txt";
        variable debug_line : line;
    begin
        if rising_edge(clk) then
            -- Monitor input requests
            if input_req_valid = '1' and input_req_ready = '1' then
                write(debug_line, string'("INPUT_REQUEST: ["));
                write(debug_line, input_req_row);
                write(debug_line, ',');
                write(debug_line, input_req_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor input provision
            if input_valid = '1' and input_ready = '1' then
                write(debug_line, string'("INPUT_PROVIDED: ["));
                write(debug_line, input_req_row);  -- Use last requested position
                write(debug_line, ',');
                write(debug_line, input_req_col);
                write(debug_line, string'("] "));
                write(debug_line, to_integer(unsigned(input_pixel(0))));
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor Conv1 outputs (Layer 0)
            if debug_conv1_valid = '1' then
                -- Always write to debug file; console reports are optional
                write(debug_line, string'("LAYER0_CONV1_OUTPUT: ["));
                write(debug_line, debug_conv1_row);
                write(debug_line, ',');
                write(debug_line, debug_conv1_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
                for i in 0 to 7 loop
                    write(debug_line, string'("  Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(debug_conv1_pixel(i))));
                    writeline(debug_file, debug_line);
                    if VERBOSE_DETAIL then
                        report "Layer0 Filter " & integer'image(i) & ": " & integer'image(to_integer(signed(debug_conv1_pixel(i))));
                    end if;
                end loop;
                debug_conv1_ready <= '1';
            else
                debug_conv1_ready <= '0';
            end if;
            
            -- Monitor Pool1 outputs (Layer 1)
            if debug_pool1_valid = '1' then
                write(debug_line, string'("LAYER1_POOL1_OUTPUT: ["));
                write(debug_line, debug_pool1_row);
                write(debug_line, ',');
                write(debug_line, debug_pool1_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
                for i in 0 to 7 loop
                    write(debug_line, string'("  Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(debug_pool1_pixel(i))));
                    writeline(debug_file, debug_line);
                    if VERBOSE_DETAIL then
                        report "Layer1 Filter " & integer'image(i) & ": " & integer'image(to_integer(signed(debug_pool1_pixel(i))));
                    end if;
                end loop;
                debug_pool1_ready <= '1';
            else
                debug_pool1_ready <= '0';
            end if;
            
            -- Monitor Conv2 outputs (Layer 2)
            if debug_conv2_valid = '1' then
                write(debug_line, string'("LAYER2_CONV2_OUTPUT: ["));
                write(debug_line, debug_conv2_row);
                write(debug_line, ',');
                write(debug_line, debug_conv2_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
                for i in 0 to 15 loop
                    write(debug_line, string'("  Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(debug_conv2_pixel(i))));
                    writeline(debug_file, debug_line);
                    if VERBOSE_DETAIL then
                        report "Layer2 Filter " & integer'image(i) & ": " & integer'image(to_integer(signed(debug_conv2_pixel(i))));
                    end if;
                end loop;
                debug_conv2_ready <= '1';
            else
                debug_conv2_ready <= '0';
            end if;
            
            -- Monitor Pool2 outputs (Layer 3)
            if debug_pool2_valid = '1' then
                write(debug_line, string'("LAYER3_POOL2_OUTPUT: ["));
                write(debug_line, debug_pool2_row);
                write(debug_line, ',');
                write(debug_line, debug_pool2_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
                for i in 0 to 15 loop
                    write(debug_line, string'("  Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(debug_pool2_pixel(i))));
                    writeline(debug_file, debug_line);
                end loop;
                debug_pool2_ready <= '1';
            else
                debug_pool2_ready <= '0';
            end if;
            
            -- Monitor final outputs (from top-level output_pixel port - Pool2 alias)
            if output_valid = '1' and output_ready = '1' then
                if VERBOSE_DETAIL then
                    report "CNN Output received";
                end if;

                -- CNN_OUTPUT header (always written to debug file)
                write(debug_line, string'("CNN_OUTPUT: ["));
                write(debug_line, output_req_row);  -- Use requested output position
                write(debug_line, ',');
                write(debug_line, output_req_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);

                for i in 0 to FINAL_NUM_FILTERS-1 loop
                    if VERBOSE_DETAIL then
                        report "  Filter " & integer'image(i) & ": " & 
                            integer'image(to_integer(signed(output_pixel(i))));
                    end if;
                    -- Write filter output to debug file
                    write(debug_line, string'("Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(output_pixel(i))));
                    writeline(debug_file, debug_line);
                end loop;
            end if;
            
            -- Monitor FC1 outputs (Layer 5) - just monitor, don't control ready
            if fc1_output_valid = '1' and fc1_output_ready = '1' then
                report "CNN FC1 Output received (64 neurons)";
                
                -- FC1_OUTPUT header
                write(debug_line, string'("FC1_OUTPUT:"));
                writeline(debug_file, debug_line);
                
                for i in 0 to FC1_NODES_OUT-1 loop
                    report "  Neuron " & integer'image(i) & ": " & 
                        integer'image(to_integer(signed(fc1_output_data(i))));
                    -- Write neuron output
                    write(debug_line, string'("  Neuron_"));
                    write(debug_line, i);
                    write(debug_line, string'(": "));
                    write(debug_line, to_integer(signed(fc1_output_data(i))));
                    writeline(debug_file, debug_line);
                end loop;
            end if;
            
            -- Monitor calc_index activity
            if debug_calc_valid = '1' then
                -- Report every 50th pixel to avoid log spam
                if debug_calc_index mod 50 = 0 then
                    report "CALC_INDEX: index=" & integer'image(debug_calc_index) & 
                           " pixel=" & integer'image(to_integer(signed(debug_calc_pixel)));
                end if;
                write(debug_line, string'("CALC_INDEX: index="));
                write(debug_line, debug_calc_index);
                write(debug_line, string'(" pixel="));
                write(debug_line, to_integer(signed(debug_calc_pixel)));
                writeline(debug_file, debug_line);
            end if;
            
            if debug_calc_done = '1' then
                write(debug_line, string'("CALC_INDEX: DONE - all 400 pixels sent"));
                writeline(debug_file, debug_line);
            end if;
        end if;
    end process;

    -- Main test process
    test_process: process
        constant FINAL_OUTPUT_SIZE : integer := 5;  -- After Conv1(26x26)->Pool1(13x13)->Conv2(11x11)->Pool2(5x5)
    begin
        -- Initialize
        rst <= '1';
        output_req_valid <= '0';
        output_ready <= '0';
        fc1_output_ready <= '0';
        use_fc_path <= '0';  -- Start with testbench controlling Pool2
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting CNN top-level test with FC1...";
        report "Test image ready - first pixel value: " & integer'image(test_image(0,0));
        report "Test image pattern - corner values: [0,0]=" & integer'image(test_image(0,0)) & 
               " [0,27]=" & integer'image(test_image(0,27)) & 
               " [27,0]=" & integer'image(test_image(27,0)) & 
               " [27,27]=" & integer'image(test_image(27,27));
        
        -- Start the CNN
        enable <= '1';
        
        -- Request all output positions (5x5 final output from Pool2)
        for out_row in 0 to FINAL_OUTPUT_SIZE-1 loop
            for out_col in 0 to FINAL_OUTPUT_SIZE-1 loop
                if VERBOSE_DETAIL then
                    report "Requesting CNN output position [" & integer'image(out_row) & "," & integer'image(out_col) & "]";
                end if;
                
                -- Send output position request (robust handshake)
                output_req_row <= out_row;
                output_req_col <= out_col;
                output_req_valid <= '1';

                -- Let DUT sample the valid (wait one clock edge)
                wait until rising_edge(clk);

                -- Wait until DUT asserts ready (may be pulsed after sampling)
                while output_req_ready /= '1' loop
                    wait until rising_edge(clk);
                end loop;

                -- Clear request on next clock edge (single-cycle pulse)
                wait until rising_edge(clk);
                output_req_valid <= '0';
                
                -- Wait for output to be ready, then accept it
                -- Set ready high BEFORE the clock edge where output_valid is '1'
                loop
                    -- Pre-assert output_ready
                    output_ready <= '1';
                    wait until rising_edge(clk);
                    -- Check if output was valid on this edge
                    if output_valid = '1' then
                        exit;  -- Both signals were high, monitor will capture
                    end if;
                end loop;
                
                -- Clear ready on next cycle
                output_ready <= '0';
                
                -- Small gap before next request
                wait for CLK_PERIOD;
            end loop;
        end loop;
        
        report "All CNN Pool2 outputs received!";
        
        -- Now switch to FC path - let calc_index control Pool2
        report "Switching to FC path - calc_index will now request Pool2 data...";
        use_fc_path <= '1';
        
        -- Wait for FC1 to complete (it processes independently)
        report "Waiting for FC1 to complete processing...";
        fc1_output_ready <= '1';
        
        -- Wait for FC1 output
        loop
            wait until rising_edge(clk);
            if fc1_output_valid = '1' then
                exit;
            end if;
        end loop;
        
        report "FC1 output received!";
        fc1_output_ready <= '0';
        
        -- Wait a few more cycles
        wait for CLK_PERIOD * 10;
        
        -- Test reset functionality
        if VERBOSE_DETAIL then
            report "Testing CNN reset functionality...";
        end if;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 5;
        
        -- Test second run (just first output position)
        if VERBOSE_DETAIL then
            report "Testing second CNN run (first position only)...";
        end if;
        
        output_req_row <= 0;
        output_req_col <= 0;
        output_req_valid <= '1';

        -- Give DUT a clock to sample the request
        wait until rising_edge(clk);

        -- Wait for acknowledgement
        while output_req_ready /= '1' loop
            wait until rising_edge(clk);
        end loop;

        wait until rising_edge(clk);
        output_req_valid <= '0';
        
        -- Fixed handshake for second run too (same pattern)
        loop
            output_ready <= '1';
            wait until rising_edge(clk);
            if output_valid = '1' then
                exit;
            end if;
        end loop;
        output_ready <= '0';
        
        if VERBOSE_DETAIL then
            report "Second CNN run completed!";
        end if;
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        if VERBOSE_DETAIL then
            report "All CNN tests completed successfully!";
        end if;
        -- Allow signals to settle for one clock period
        wait for CLK_PERIOD;
        -- Explicitly stop simulation when the simulator supports VHDL-2008 std.env
        -- This forces immediate termination; remove/comment out if your simulator doesn't support std.env
        std.env.stop(0);
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        -- Simple watchdog pattern used by other testbenches in this repo
        wait for 2000 ms;  -- Longer timeout for full CNN
        if not test_done then
            report "CNN TEST TIMEOUT - Test did not complete within expected time" severity failure;
        end if;
        wait;
    end process;

end Behavioral;
