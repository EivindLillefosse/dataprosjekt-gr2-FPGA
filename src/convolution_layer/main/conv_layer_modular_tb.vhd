----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Modular Convolution Layer Testbench
-- Module Name: conv_layer_modular_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: Testbench for modular convolution layer
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

entity conv_layer_modular_tb is
end conv_layer_modular_tb;

architecture Behavioral of conv_layer_modular_tb is
    -- Test parameters
    constant IMAGE_SIZE : integer := 28;
    constant KERNEL_SIZE : integer := 3;
    constant INPUT_CHANNELS : integer := 1;
    constant NUM_FILTERS : integer := 8;
    constant STRIDE : integer := 1;
    constant BLOCK_SIZE : integer := 2;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- UUT signals
    signal clk : STD_LOGIC := '0';
    signal rst : STD_LOGIC := '0';
    signal enable : STD_LOGIC := '0';
    
    -- Output request TO DUT (testbench acts as downstream)
    signal pixel_out_req_row   : integer := 0;
    signal pixel_out_req_col   : integer := 0;
    signal pixel_out_req_valid : std_logic := '0';
    signal pixel_out_req_ready : std_logic;
    
    -- Input request FROM DUT (testbench acts as upstream)
    signal pixel_in_req_row    : integer;
    signal pixel_in_req_col    : integer;
    signal pixel_in_req_valid  : std_logic;
    signal pixel_in_req_ready  : std_logic := '0';
    
    -- Input data TO DUT (16-bit for flexibility, lower 8 bits used for Layer 0)
    signal pixel_in            : WORD_ARRAY_16(0 to INPUT_CHANNELS-1);
    signal pixel_in_valid      : std_logic := '0';
    signal pixel_in_ready      : std_logic;
    
    -- Output data FROM DUT (16-bit outputs)
    signal pixel_out           : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    signal pixel_out_valid     : std_logic;
    signal pixel_out_ready     : std_logic := '0';
    
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
    signal pixel_request_row : integer := 0;
    signal pixel_request_col : integer := 0;
    
    -- Debug signal for MAC intermediate values
    signal debug_mac_results : WORD_ARRAY_16(0 to NUM_FILTERS-1);

    -- Helper: convert std_logic_vector to hex string (prefixed with 0x)
    function slv_to_hex(bv : std_logic_vector) return string is
        variable u       : unsigned(bv'range) := unsigned(bv);
        variable val     : integer := to_integer(u);
        variable nibbles : integer := (bv'length + 3) / 4;
        variable outstr  : string(1 to 2 + nibbles);
        variable digit   : integer;
        variable divisor : integer;
    begin
        outstr(1) := '0';
        outstr(2) := 'x';
        for i in 1 to nibbles loop
            divisor := 16 ** (nibbles - i);
            digit := (val / divisor) mod 16;
            case digit is
                when 0  => outstr(i+2) := '0';
                when 1  => outstr(i+2) := '1';
                when 2  => outstr(i+2) := '2';
                when 3  => outstr(i+2) := '3';
                when 4  => outstr(i+2) := '4';
                when 5  => outstr(i+2) := '5';
                when 6  => outstr(i+2) := '6';
                when 7  => outstr(i+2) := '7';
                when 8  => outstr(i+2) := '8';
                when 9  => outstr(i+2) := '9';
                when 10 => outstr(i+2) := 'A';
                when 11 => outstr(i+2) := 'B';
                when 12 => outstr(i+2) := 'C';
                when 13 => outstr(i+2) := 'D';
                when 14 => outstr(i+2) := 'E';
                when 15 => outstr(i+2) := 'F';
                when others => outstr(i+2) := '?';
            end case;
        end loop;
        return outstr;
    end function;

    -- Helper: convert std_logic_vector to plain binary string
    function slv_to_bin(bv : std_logic_vector) return string is
        variable outstr : string(1 to bv'length);
        variable idx : integer := 1;
    begin
        for i in bv'range loop
            if bv(i) = '1' then
                outstr(idx) := '1';
            else
                outstr(idx) := '0';
            end if;
            idx := idx + 1;
        end loop;
        return outstr;
    end function;

    -- Helper: interpret std_logic_vector as signed Q1.6 and return decimal string
    function slv_to_q1_6(bv : std_logic_vector) return string is
        variable sval    : integer := to_integer(signed(bv));
        variable absval  : integer;
        variable intpart : integer;
        variable frac    : integer;
        variable frac3   : integer;
        variable signstr : string(1 to 1);
        variable s_int   : string(1 to 20);
        variable s_frac  : string(1 to 3);
        variable s_out   : string(1 to 30);
        variable len_int : integer;
        variable len_out : integer := 0;
        variable tmp     : string(1 to 20);
        variable trim_idx: integer;
        -- local temporaries declared here (declarative region)
        variable tmp_frac   : string(1 to 10);
        variable frac_digits: integer;
    begin
        if sval < 0 then
            absval := -sval;
            signstr(1) := '-';
        else
            absval := sval;
            signstr(1) := ' ';
        end if;

        intpart := absval / 64; -- Q1.6 -> divide by 2^6
        frac := absval mod 64;   -- fractional bits
        -- fractional part scaled to 3 decimal digits with rounding
        frac3 := (frac * 1000 + 32) / 64;
        if frac3 = 1000 then
            intpart := intpart + 1;
            frac3 := 0;
        end if;

        -- integer part as string
        tmp := integer'image(intpart);
        -- trim leading spaces from integer'image
        trim_idx := tmp'low;
        while trim_idx <= tmp'high and tmp(trim_idx) = ' ' loop
            trim_idx := trim_idx + 1;
        end loop;
        len_int := tmp'high - trim_idx + 1;
        for i in 1 to len_int loop
            s_int(i) := tmp(trim_idx + i - 1);
        end loop;

        -- fractional part padded to 3 digits
        tmp_frac := integer'image(frac3);
        -- find first non-space
        trim_idx := tmp_frac'low;
        while trim_idx <= tmp_frac'high and tmp_frac(trim_idx) = ' ' loop
            trim_idx := trim_idx + 1;
        end loop;
        -- fill s_frac with padding zeros then digits
        if trim_idx > tmp_frac'high then
            s_frac := (others => '0');
        else
            frac_digits := tmp_frac'high - trim_idx + 1;
            -- pad on the left
            for i in 1 to 3-frac_digits loop
                s_frac(i) := '0';
            end loop;
            for i in 1 to frac_digits loop
                s_frac(3-frac_digits+i) := tmp_frac(trim_idx + i - 1);
            end loop;
        end if;

        -- build output: optional sign, integer, dot, 3 frac digits
        len_out := 0;
        if signstr(1) = '-' then
            len_out := len_out + 1;
            s_out(len_out) := '-';
        end if;
        for i in 1 to len_int loop
            len_out := len_out + 1;
            s_out(len_out) := s_int(i);
        end loop;
        len_out := len_out + 1;
        s_out(len_out) := '.';
        for i in 1 to 3 loop
            len_out := len_out + 1;
            s_out(len_out) := s_frac(i);
        end loop;

        return s_out(1 to len_out);
    end function;

    -- Helper: interpret std_logic_vector as signed Q2.12 and fill an output buffer
    procedure slv_to_q2_12(bv : std_logic_vector; out_buf : out string(1 to 40)) is
        variable sval    : integer := to_integer(signed(bv));
        variable absval  : integer;
        variable intpart : integer;
        variable frac    : integer;
        variable frac3   : integer;
        variable signstr : string(1 to 1);
        variable s_int   : string(1 to 20);
        variable s_frac  : string(1 to 3);
        variable tmp     : string(1 to 20);
        variable trim_idx: integer;
        variable tmp_frac: string(1 to 20);
        variable frac_digits: integer;
        variable i       : integer;
        variable len_int : integer;
        variable len_out : integer := 0;
    begin
        -- initialize buffer with spaces
        for i in out_buf'range loop
            out_buf(i) := ' ';
        end loop;

        if sval < 0 then
            absval := -sval;
            signstr(1) := '-';
        else
            absval := sval;
            signstr(1) := ' ';
        end if;

        intpart := absval / 4096; -- Q2.12 -> divide by 2^12
        frac := absval mod 4096;   -- fractional bits
        -- fractional part scaled to 3 decimal digits with rounding
        frac3 := (frac * 1000 + 2048) / 4096;
        if frac3 = 1000 then
            intpart := intpart + 1;
            frac3 := 0;
        end if;

        -- integer part as string
        tmp := integer'image(intpart);
        -- trim leading spaces from integer'image
        trim_idx := tmp'low;
        while trim_idx <= tmp'high and tmp(trim_idx) = ' ' loop
            trim_idx := trim_idx + 1;
        end loop;
        len_int := tmp'high - trim_idx + 1;
        for i in 1 to len_int loop
            s_int(i) := tmp(trim_idx + i - 1);
        end loop;

        -- fractional part padded to 3 digits
        tmp_frac := integer'image(frac3);
        -- find first non-space
        trim_idx := tmp_frac'low;
        while trim_idx <= tmp_frac'high and tmp_frac(trim_idx) = ' ' loop
            trim_idx := trim_idx + 1;
        end loop;
        -- fill s_frac with padding zeros then digits
        if trim_idx > tmp_frac'high then
            s_frac := (others => '0');
        else
            frac_digits := tmp_frac'high - trim_idx + 1;
            -- pad on the left
            for i in 1 to 3-frac_digits loop
                s_frac(i) := '0';
            end loop;
            for i in 1 to frac_digits loop
                s_frac(3-frac_digits+i) := tmp_frac(trim_idx + i - 1);
            end loop;
        end if;

        -- build output into out_buf starting at position 1
        len_out := 0;
        if signstr(1) = '-' then
            len_out := len_out + 1;
            out_buf(len_out) := '-';
        end if;
        for i in 1 to len_int loop
            len_out := len_out + 1;
            out_buf(len_out) := s_int(i);
        end loop;
        len_out := len_out + 1;
        out_buf(len_out) := '.';
        for i in 1 to 3 loop
            len_out := len_out + 1;
            out_buf(len_out) := s_frac(i);
        end loop;
    end procedure;

begin
    -- Unit Under Test (UUT) - Using the modular version
    uut: entity work.conv_layer_modular
        generic map (
            IMAGE_SIZE => IMAGE_SIZE,
            KERNEL_SIZE => KERNEL_SIZE,
            INPUT_CHANNELS => INPUT_CHANNELS,
            NUM_FILTERS => NUM_FILTERS,
            STRIDE => STRIDE,
            BLOCK_SIZE => BLOCK_SIZE
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            enable              => enable,
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

    -- Upstream provider process (simulates input layer providing pixel data)
    -- Responds to input position requests from the conv layer
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
                    -- Provide data from test image
                    if pending_row >= 0 and pending_row < IMAGE_SIZE and 
                       pending_col >= 0 and pending_col < IMAGE_SIZE then
                        -- Valid pixel (extend 8-bit to 16-bit for Layer 0 compatibility)
                        pixel_in(0) <= std_logic_vector(resize(to_unsigned(test_image(pending_row, pending_col), 8), 16));
                        report "Upstream: Providing pixel [" & integer'image(pending_row) & "," & 
                               integer'image(pending_col) & "] = " & 
                               integer'image(test_image(pending_row, pending_col)) severity note;
                    else
                        -- Out of bounds - provide zero padding
                        pixel_in(0) <= (others => '0');
                        report "Upstream: Providing padding pixel [" & integer'image(pending_row) & "," & 
                               integer'image(pending_col) & "] = 0" severity note;
                    end if;
                    pixel_in_valid <= '1';
                    req_pending := '0';
                end if;
                
                -- If conv layer requests an input position, acknowledge and schedule data
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

    -- Output monitor process with intermediate value capture
    output_monitor: process(clk)
        file debug_file : text open write_mode is "modular_intermediate_debug.txt";
        variable debug_line : line;
    begin
        if rising_edge(clk) then
            -- Monitor input requests
            if pixel_in_req_valid = '1' then
                write(debug_line, string'("INPUT_REQUEST: ["));
                write(debug_line, pixel_in_req_row);
                write(debug_line, ',');
                write(debug_line, pixel_in_req_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor input provision
            if pixel_in_valid = '1' then
                write(debug_line, string'("INPUT_PROVIDED: ["));
                write(debug_line, pixel_in_req_row);
                write(debug_line, ',');
                write(debug_line, pixel_in_req_col);
                write(debug_line, string'("] "));
                write(debug_line, to_integer(signed(pixel_in(0))));
                writeline(debug_file, debug_line);
            end if;
            
            -- Monitor final outputs
            if pixel_out_valid = '1' and pixel_out_ready = '1' then
                report "Modular Output at position [" & integer'image(pixel_out_req_row) & "," & integer'image(pixel_out_req_col) & "]";
                
                -- MODULAR_OUTPUT header (include explicit metadata: scale and bitwidth)
                write(debug_line, string'("MODULAR_OUTPUT: ["));
                write(debug_line, pixel_out_req_row);
                write(debug_line, ',');
                write(debug_line, pixel_out_req_col);
                write(debug_line, ']');
                writeline(debug_file, debug_line);

                -- Output meta: 16-bit outputs (Q2.12 format before final scaling)
                write(debug_line, string'("OUTPUT_META: scale=4096 bits=16"));
                writeline(debug_file, debug_line);

                for i in 0 to NUM_FILTERS-1 loop
                    -- Human readable report (keeps existing reports for simulator console)
                    report "  Filter " & integer'image(i) & ": " & integer'image(to_integer(signed(pixel_out(i))));

                    -- Write filter output as hex (MSB-first) and unsigned decimal to avoid signed printing ambiguity
                    write(debug_line, string'("Filter_"));
                    write(debug_line, i);
                    write(debug_line, string'("_hex: "));
                    write(debug_line, slv_to_hex(pixel_out(i)));
                    write(debug_line, string'("  dec: "));
                    write(debug_line, to_integer(unsigned(pixel_out(i))));
                    writeline(debug_file, debug_line);
                end loop;
            end if;
        end if;
    end process;

    -- Main test process (acts as downstream consumer requesting outputs)
    test_process: process
        constant OUT_SIZE : integer := IMAGE_SIZE - KERNEL_SIZE + 1;  -- 28-3+1=26
        variable received_val : integer;
    begin
        -- Initialize
        rst <= '1';
        enable <= '0';
        pixel_out_req_valid <= '0';
        pixel_out_ready <= '0';
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
        report "Starting MODULAR convolution layer test (Request/Response Protocol)...";
        report "Test image ready - first pixel value: " & integer'image(test_image(0,0));
        report "Output size: " & integer'image(OUT_SIZE) & "x" & integer'image(OUT_SIZE);
        
        -- Start the convolution
        enable <= '1';
        
        -- Request all output positions
        for out_row in 0 to OUT_SIZE-1 loop
            for out_col in 0 to OUT_SIZE-1 loop
                report "Requesting output position [" & integer'image(out_row) & "," & integer'image(out_col) & "]";
                
                -- Send output position request
                pixel_out_req_row <= out_row;
                pixel_out_req_col <= out_col;
                pixel_out_req_valid <= '1';
                
                -- Wait for DUT to acknowledge request
                wait until rising_edge(clk) and pixel_out_req_ready = '1';
                
                -- Clear request on next clock edge (single-cycle pulse)
                wait until rising_edge(clk);
                pixel_out_req_valid <= '0';
                
                -- Wait for output to be ready
                wait until rising_edge(clk) and pixel_out_valid = '1';
                
                -- Accept the output
                pixel_out_ready <= '1';
                wait until rising_edge(clk);
                pixel_out_ready <= '0';
                
                -- Small gap before next request
                wait for CLK_PERIOD;
            end loop;
        end loop;
        
        report "MODULAR convolution layer completed successfully!";
        
        -- Wait a few more cycles
        wait for CLK_PERIOD * 10;
        
        -- Test reset functionality
        report "Testing MODULAR reset functionality...";
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 5;
        
        -- Test multiple runs (request a few more positions to verify)
        report "Testing second MODULAR convolution run...";
        enable <= '1';
        
        -- Request a few more output positions
        for i in 0 to 4 loop
            pixel_out_req_row <= i;
            pixel_out_req_col <= i;
            pixel_out_req_valid <= '1';
            wait for CLK_PERIOD;
            while pixel_out_req_ready = '0' loop
                wait for CLK_PERIOD;
            end loop;
            pixel_out_req_valid <= '0';
            
            -- Wait for output
            pixel_out_ready <= '1';
            wait for CLK_PERIOD;
            while pixel_out_valid = '0' loop
                wait for CLK_PERIOD;
            end loop;
            pixel_out_ready <= '0';
        end loop;
        
        report "Second MODULAR convolution completed!";
        
        wait for CLK_PERIOD * 10;
        
    test_done <= true;
    report "All MODULAR tests completed successfully!";
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
        wait for 1000 ms;
        if not test_done then
            report "MODULAR TEST TIMEOUT - Test did not complete within expected time" severity failure;
        end if;
        wait;
    end process;

end Behavioral;