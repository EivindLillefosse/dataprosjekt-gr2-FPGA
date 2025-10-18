----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: MAC Testbench
-- Module Name: MAC_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for MAC (Multiply-Accumulate) unit
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MAC_tb is
end MAC_tb;

architecture Behavioral of MAC_tb is

    -- Test parameters
    constant WIDTH_A : integer := 8;
    constant WIDTH_B : integer := 8;
    constant WIDTH_P : integer := 16;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- Test data types and constants
    type int_array is array (0 to 5) of integer;
    constant pixel_values  : int_array := (1, 2, 3, 4, 5, 6);
    constant weight_values : int_array := (1, 0, -1, 1, 0, -1);
    
    -- UUT signals
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '0';
    signal clear     : std_logic := '0';
    signal pixel_in  : std_logic_vector(WIDTH_A-1 downto 0) := (others => '0');
    signal weights   : std_logic_vector(WIDTH_B-1 downto 0) := (others => '0');
    signal valid     : std_logic := '0';
    signal result    : std_logic_vector(WIDTH_P-1 downto 0);
    signal done      : std_logic;
    
    -- Test control
    signal test_done : boolean := false;

    -- Fixed-point settings: signed Q1.6 inputs (6 fractional bits)
    constant FRAC_BITS : integer := 6;
    -- Per-operation watchdog (in clock cycles)
    constant MAX_WAIT_CYCLES : integer := 1000;

    -- Convert a real value to fixed-point integer representation with 'bits' fractional bits
    function real_to_fixed(val : real; bits : integer) return integer is
        variable scaled : real := val * real(2 ** bits);
        variable res : integer;
    begin
        if scaled >= 0.0 then
            res := integer(scaled + 0.5);
        else
            res := integer(scaled - 0.5);
        end if;
        return res;
    end function;

    -- Clamp an integer to signed range for a given width
    function clamp_int(val : integer; width : integer) return integer is
        variable minv : integer := - (2 ** (width - 1));
        variable maxv : integer :=   2 ** (width - 1) - 1;
        variable v : integer := val;
    begin
        if v < minv then
            return minv;
        elsif v > maxv then
            return maxv;
        else
            return v;
        end if;
    end function;

    -- Helper: wrap an integer to two's complement signed range for given bit width
    function wrap_to_twos_complement(val : integer; bits : integer) return integer is
        variable modulus : integer := 2 ** bits;
        variable v : integer := val mod modulus;
    begin
        if v < 0 then
            v := v + modulus;
        end if;
        if v >= 2 ** (bits - 1) then
            return v - modulus;
        else
            return v;
        end if;
    end function;


begin

    -- Unit Under Test
    uut: entity work.MAC
        generic map (
            width_a => WIDTH_A,
            width_b => WIDTH_B,
            width_p => WIDTH_P
        )
        port map (
            clk      => clk,
            rst      => rst,
            pixel_in => pixel_in,
            weights  => weights,
            valid    => valid,
            clear    => clear,
            result   => result,
            done     => done
        );

    -- Clock process
    clk_process: process
    begin
        wait for CLK_PERIOD/2;
        clk <= not clk;
    end process;

    -- Test process
    test_process: process
        variable expected_acc : integer := 0;
        variable seed : integer := 42;
        variable rand_a : integer := 0;
        variable rand_b : integer := 0;
        variable pix_fp : integer := 0;
        variable wt_fp  : integer := 0;
        variable ap : integer := 0;
        variable aw : integer := 0;
        variable p2 : integer := 0;
        variable w2 : integer := 0;
        variable ap2 : integer := 0;
        variable aw2 : integer := 0;
        variable pixs : integer := 0;
        variable wts : integer := 0;
        variable ap3 : integer := 0;
        variable aw3 : integer := 0;
        variable wait_cycle : integer := 0;
    begin
        -- Initialize
        rst <= '1';
        valid <= '0';
        clear <= '0';
        pixel_in <= (others => '0');
        weights <= (others => '0');
        
        wait for CLK_PERIOD * 2;
        rst <= '0';
        
        wait for CLK_PERIOD * 2;
        
    report "At " & integer'image(now / 1 ns) & " ns: Starting MAC test...";
        
        -- Test case 1: Basic accumulation with positive values (scaled to Q1.6)
    report "At " & integer'image(now / 1 ns) & " ns: Test 1: Basic accumulation with positive values";
        expected_acc := 0;
        
        -- Compute with small Q1.6 values: i/8 to keep well within range
        for i in 1 to 3 loop
            pix_fp := clamp_int(real_to_fixed(real(i) / 8.0, FRAC_BITS), WIDTH_A);
            wt_fp  := clamp_int(real_to_fixed(real(i) / 8.0, FRAC_BITS), WIDTH_B);
            pixel_in <= std_logic_vector(to_signed(pix_fp, WIDTH_A));
            weights <= std_logic_vector(to_signed(wt_fp, WIDTH_B));
            valid <= '1';
            wait for CLK_PERIOD;
            -- guarded wait for done with per-cycle debug and timeout
            wait_cycle := 0;
            loop
                wait for CLK_PERIOD;
                wait_cycle := wait_cycle + 1;
                report "DBG: wait-loop cycle=" & integer'image(wait_cycle) &
                       " valid='" & std_logic'image(valid) & "' done='" & std_logic'image(done) &
                       "' result=" & integer'image(to_integer(signed(result))) &
                       " pix=" & integer'image(to_integer(signed(pixel_in))) &
                       " wt=" & integer'image(to_integer(signed(weights)));
                exit when done = '1' or wait_cycle >= MAX_WAIT_CYCLES;
            end loop;
            if done /= '1' then
                -- Non-fatal: report an error but attempt to recover and continue tests.
                report "Error: done timeout at " & integer'image(now / 1 ns) &
                       " (waited " & integer'image(wait_cycle) & " cycles, MAX=" & integer'image(MAX_WAIT_CYCLES) & ")" severity error;
                -- Try graceful recovery: deassert valid, wait a few cycles, pulse clear to reset internal state.
                valid <= '0';
                wait for CLK_PERIOD * 3;
                clear <= '1';
                wait for CLK_PERIOD;
                clear <= '0';
                wait for CLK_PERIOD * 2;
            end if;
            valid <= '0';
            
            ap := to_integer(signed(pixel_in));
            aw := to_integer(signed(weights));
            expected_acc := wrap_to_twos_complement(expected_acc + (ap * aw), WIDTH_P);
            
         report "At " & integer'image(now / 1 ns) & " ns:   Computation " & integer'image(i) & ": " & 
             integer'image(i) & " * " & integer'image(i) & 
             " -> accumulated result = " & integer'image(to_integer(signed(result)));
            
            assert to_integer(signed(result)) = expected_acc
                report "Error: At " & integer'image(now / 1 ns) & " ns: MAC result mismatch at computation " & integer'image(i) & 
                       ", expected " & integer'image(expected_acc) & " but got " & integer'image(to_integer(signed(result)))
                severity error;
            wait for CLK_PERIOD*2;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 2: Clear and restart
    report "At " & integer'image(now / 1 ns) & " ns: Test 2: Clear and restart accumulation";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        
        wait for CLK_PERIOD * 2;
        
        expected_acc := 0;
        
    -- Simple test after clear: scaled 5/8 * 2/8 in Q1.6
    p2 := clamp_int(real_to_fixed(5.0/8.0, FRAC_BITS), WIDTH_A);
    w2 := clamp_int(real_to_fixed(2.0/8.0, FRAC_BITS), WIDTH_B);
    pixel_in <= std_logic_vector(to_signed(p2, WIDTH_A));
    weights <= std_logic_vector(to_signed(w2, WIDTH_B));
        valid <= '1';
        wait for CLK_PERIOD;
        
        -- guarded wait instead of unconditional wait until (protect against hangs)
        wait_cycle := 0;
        loop
            wait for CLK_PERIOD;
            wait_cycle := wait_cycle + 1;
            report "DBG: wait-loop (test2) cycle=" & integer'image(wait_cycle) &
                   " valid='" & std_logic'image(valid) & "' done='" & std_logic'image(done) &
                   "' result=" & integer'image(to_integer(signed(result)));
            exit when done = '1' or wait_cycle >= MAX_WAIT_CYCLES;
        end loop;
        if done /= '1' then
            report "Error: done timeout in Test 2 at " & integer'image(now / 1 ns) &
                   " (waited " & integer'image(wait_cycle) & " cycles)" severity error;
            valid <= '0';
            wait for CLK_PERIOD * 3;
            clear <= '1';
            wait for CLK_PERIOD;
            clear <= '0';
            wait for CLK_PERIOD * 2;
        else
            wait for CLK_PERIOD;
            valid <= '0';
        end if;
        
    ap2 := to_integer(signed(pixel_in));
    aw2 := to_integer(signed(weights));
    expected_acc := wrap_to_twos_complement(ap2 * aw2, WIDTH_P);
        
    report "At " & integer'image(now / 1 ns) & " ns:   After clear: 5 * 2 = " & integer'image(to_integer(signed(result)));
        
        assert to_integer(signed(result)) = expected_acc
            report "Error: At " & integer'image(now / 1 ns) & " ns: MAC result after clear mismatch" & 
                   ", expected " & integer'image(expected_acc) & " but got " & integer'image(to_integer(signed(result)))
            severity error;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 3: Mixed positive and negative values
    report "At " & integer'image(now / 1 ns) & " ns: Test 3: Mixed positive and negative values";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
        expected_acc := 0;
        
        -- Test pattern: use scaled values /8 to stay inside Q1.6 range
        for i in 0 to 5 loop
            pixs := clamp_int(real_to_fixed(real(pixel_values(i)) / 8.0, FRAC_BITS), WIDTH_A);
            wts  := clamp_int(real_to_fixed(real(weight_values(i)) / 8.0, FRAC_BITS), WIDTH_B);
            pixel_in <= std_logic_vector(to_signed(pixs, WIDTH_A));
            weights <= std_logic_vector(to_signed(wts, WIDTH_B));
            valid <= '1';
            wait for CLK_PERIOD;
            -- guarded wait for done
            wait_cycle := 0;
            loop
                wait for CLK_PERIOD;
                wait_cycle := wait_cycle + 1;
                report "DBG: wait-loop cycle=" & integer'image(wait_cycle) &
                       " valid='" & std_logic'image(valid) & "' done='" & std_logic'image(done) &
                       "' result=" & integer'image(to_integer(signed(result))) &
                       " pix=" & integer'image(to_integer(signed(pixel_in))) &
                       " wt=" & integer'image(to_integer(signed(weights)));
                exit when done = '1' or wait_cycle >= MAX_WAIT_CYCLES;
            end loop;
            if done /= '1' then
                report "Error: done timeout at " & integer'image(now / 1 ns) &
                       " (waited " & integer'image(wait_cycle) & " cycles)" severity error;
                -- Attempt recovery
                valid <= '0';
                wait for CLK_PERIOD * 3;
                clear <= '1';
                wait for CLK_PERIOD;
                clear <= '0';
                wait for CLK_PERIOD * 2;
            end if;
            valid <= '0';
            
            ap3 := to_integer(signed(pixel_in));
            aw3 := to_integer(signed(weights));
            expected_acc := wrap_to_twos_complement(expected_acc + (ap3 * aw3), WIDTH_P);
            
         report "At " & integer'image(now / 1 ns) & " ns:   Computation " & integer'image(i) & ": " & 
             integer'image(pixel_values(i)) & " * " & integer'image(weight_values(i)) & 
             " -> accumulated result = " & integer'image(to_integer(signed(result)));
            
            assert to_integer(signed(result)) = expected_acc
                report "Error: At " & integer'image(now / 1 ns) & " ns: MAC result mismatch at computation " & integer'image(i) & 
                       ", expected " & integer'image(expected_acc) & " but got " & integer'image(to_integer(signed(result)))
                severity error;
            wait for CLK_PERIOD*2;
        end loop;
        
        wait for CLK_PERIOD * 3;
        
        -- Test case 4: Zero values
    report "At " & integer'image(now / 1 ns) & " ns: Test 4: Zero values";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD;
        
    pixel_in <= (others => '0');
    weights <= std_logic_vector(to_signed(clamp_int(real_to_fixed(5.0/8.0, FRAC_BITS), WIDTH_B), WIDTH_B));
        valid <= '1';
        wait for CLK_PERIOD;
        -- guarded wait for done
        wait_cycle := 0;
        loop
            wait for CLK_PERIOD;
            wait_cycle := wait_cycle + 1;
            report "DBG: wait-loop cycle=" & integer'image(wait_cycle) &
                   " valid='" & std_logic'image(valid) & "' done='" & std_logic'image(done) &
                   "' result=" & integer'image(to_integer(signed(result))) &
                   " pix=" & integer'image(to_integer(signed(pixel_in))) &
                   " wt=" & integer'image(to_integer(signed(weights)));
            exit when done = '1' or wait_cycle >= 200;
        end loop;
        if done /= '1' then
            report "Failure: Error: done timeout at " & integer'image(now / 1 ns) severity failure;
        end if;
        wait for CLK_PERIOD;
        valid <= '0';
        
    report "At " & integer'image(now / 1 ns) & " ns:   0 * 5 = " & integer'image(to_integer(signed(result)));
        
     assert to_integer(signed(result)) = 0
            report "Error: At " & integer'image(now / 1 ns) & " ns: Zero pixel should result in zero" & 
                   ", expected 0 but got " & integer'image(to_integer(signed(result)))
            severity error;
        
    report "At " & integer'image(now / 1 ns) & " ns: MAC test completed successfully!";
        
        wait for CLK_PERIOD * 10;
        
        test_done <= true;
        wait;
    end process;

    -- Timeout watchdog
    timeout_watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "Error: At " & integer'image(now / 1 ns) & " ns: TEST TIMEOUT - MAC test did not complete" severity failure;
        end if;
        wait;
    end process;

end Behavioral;