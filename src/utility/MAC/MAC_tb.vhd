----------------------------------------------------------------------------------
-- MAC Testbench (clean) - matches current MAC entity with load/ce/clear
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity MAC_tb is
end MAC_tb;

architecture Behavioral of MAC_tb is
    -- Component declaration matching MAC.vhd
    component MAC is
        generic (
            WIDTH_A : integer := 8;
            WIDTH_B : integer := 8;
            WIDTH_P : integer := 16
        );
        Port (
            clk      : in  STD_LOGIC;
            load     : in  STD_LOGIC;
            ce       : in  STD_LOGIC;
            clear    : in  STD_LOGIC;
            pixel_in : in  signed (WIDTH_A-1 downto 0);
            weights  : in  signed (WIDTH_B-1 downto 0);
            result   : out signed (WIDTH_P-1 downto 0)
        );
    end component;

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- Signals (Q1.6 encoding with 8-bit inputs and 16-bit accumulator result)
    signal clk : std_logic := '0';
    signal load : std_logic := '0';
    signal ce   : std_logic := '0';
    signal clear : std_logic := '0';
    signal pixel_in : signed(7 downto 0) := (others => '0'); -- WIDTH_A = 8 (Q1.6)
    signal weights : signed(7 downto 0) := (others => '0');  -- WIDTH_B = 8 (Q1.6)
    signal result : signed(15 downto 0) := (others => '0');   -- WIDTH_P = 16 (Q2.12)

    -- Test control
    signal test_done : boolean := false;

    -- Helper functions
    -- Convert integer literal to Q1.6 signed representation with WIDTH=8
    function int_to_q16(int_val : integer) return signed is
    begin
        return to_signed(int_val * 2**6, 8);
    end function;

    type int9_t is array (0 to 8) of integer;
    -- New small test values within Q1.6 range (-2..+1.984)
    constant pixels_tb : int9_t := (1,0,-1,1,-1,0,1,0,-1);
    constant filt_tb   : int9_t := (1,-1,1,0,1,-1,0,1,-1);

begin
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

    -- DUT instantiation (use 8/8/16 to match Q1.6 inputs and Q2.12 output)
    dut: MAC
        generic map (
            WIDTH_A => 8,
            WIDTH_B => 8,
            WIDTH_P => 16
        )
        port map (
            clk => clk,
            load => load,
            ce => ce,
            clear => clear,
            pixel_in => pixel_in,
            weights => weights,
            result => result
        );

    -- Test process
    test_process: process
        variable result_int : integer;
        variable expected_q16 : integer;
        variable expected_q212 : integer;
    begin
        report "=== MAC Testbench Start ===";

        -- Clear accumulator synchronously
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';
        wait for CLK_PERIOD/2;

        -- Test 1: Single multiplication
        report "--- Test 1: Single multiplication ---";
    -- For single product, set load=1 so accumulator is cleared and we get product
    load <= '1';
    pixel_in <= int_to_q16(pixels_tb(0)); -- 1
    weights <= int_to_q16(filt_tb(0));    -- 1
    -- Assert CE for three clock cycles (required by DUT)
    ce <= '1';
    wait for CLK_PERIOD*3; -- keep CE high for 3 cycles
    ce <= '0';
    wait for CLK_PERIOD; -- let outputs settle and allow load to be sampled

        -- Read DUT output and compare with expected values
        result_int := to_integer(result);
        report "Result: " & integer'image(result_int);

    -- Compute expected results for Test 1 (pixels_tb(0) * filt_tb(0)) in Q2.12
    expected_q16 := pixels_tb(0) * filt_tb(0); -- integer product
    expected_q212 := expected_q16 * 2**12; -- Q2.12 scaled

        if result_int = expected_q212 then
        report "PASS: Test 1 - matches Q2.12 expected value: " & integer'image(expected_q212);
        elsif result_int = expected_q16 then
            report "FAIL: Test 1 - result in Q1.6 (" & integer'image(expected_q16) & ") instead of Q2.12 (" & integer'image(expected_q212) & ")";
        else
            report "FAIL: Test 1 - unexpected result: " & integer'image(result_int) & ", expected Q2.12=" & integer'image(expected_q212);
        end if;

        wait for CLK_PERIOD * 2;

        -- Test 2: Accumulation of 3 products
        report "--- Test 2: Accumulation of 3 products ---";
        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';

    load <= '0';

        -- Product 1: pixels_tb(1) * filt_tb(1)
    pixel_in <= int_to_q16(pixels_tb(1));
    weights <= int_to_q16(filt_tb(1));
    load <= '0';
    ce <= '1'; wait for CLK_PERIOD*3; ce <= '0'; wait for CLK_PERIOD;
        result_int := to_integer(result); report "After product 1: " & integer'image(result_int);

        -- Product 2: 3 * 14
    pixel_in <= int_to_q16(pixels_tb(2));
    weights <= int_to_q16(filt_tb(2));
    load <= '0';
    ce <= '1'; wait for CLK_PERIOD*3; ce <= '0'; wait for CLK_PERIOD;
        result_int := to_integer(result); report "After product 2: " & integer'image(result_int);

        -- Product 3: 4 * -8
    pixel_in <= int_to_q16(pixels_tb(3));
    weights <= int_to_q16(filt_tb(3));
    load <= '1';
    ce <= '1'; wait for CLK_PERIOD*3; ce <= '0'; wait for CLK_PERIOD;
        result_int := to_integer(result); report "After product 3: " & integer'image(result_int);

    -- Test 2 expected values (3 products) in Q2.12
    expected_q16 := pixels_tb(1)*filt_tb(1) + pixels_tb(2)*filt_tb(2) + pixels_tb(3)*filt_tb(3);
    expected_q212 := expected_q16 * 2**12; -- scale to Q2.12

        if result_int = expected_q212 then
        report "PASS: Test 2 - accumulation matches Q2.12 (" & integer'image(expected_q212) & ")";
        elsif result_int = expected_q16 then
            report "FAIL: Test 2 - accumulation in Q1.6 (" & integer'image(expected_q16) & ")";
        else
            report "FAIL: Test 2 - unexpected result: " & integer'image(result_int) & ", expected Q2.12=" & integer'image(expected_q212);
        end if;

        wait for CLK_PERIOD * 2;

        -- Test 3: Full 3x3 convolution (position [0,1], Filter 1)
    report "--- Test 3: Full 3x3 convolution ---";
    clear <= '1'; wait for CLK_PERIOD; clear <= '0';
    load <= '0'; -- start accumulation

        for i in 0 to 8 loop
            pixel_in <= int_to_q16(pixels_tb(i));
            weights <= int_to_q16(filt_tb(i));
            load <= '0';
            ce <= '1'; wait for CLK_PERIOD*3; ce <= '0'; wait for CLK_PERIOD;
        end loop;
        -- after finishing the 3x3 inputs, assert load to stop accumulation (pulse)
        load <= '1';
        -- sample load with one CE cycle to update reg_load in DUT
        ce <= '1'; wait for CLK_PERIOD*1; ce <= '0'; wait for CLK_PERIOD;

        result_int := to_integer(result);
        report "Final accumulated result: " & integer'image(result_int);

    -- Test 3 expected values (full 3x3 conv) computed from arrays
    expected_q16 := 0;
    for i in 0 to 8 loop
        expected_q16 := expected_q16 + pixels_tb(i) * filt_tb(i);
    end loop;
    expected_q212 := expected_q16 * 2**12;

        report "Expected if Q1.6 accumulation: " & integer'image(expected_q16);
        report "Expected if Q2.12 accumulation: " & integer'image(expected_q212);

        if result_int = expected_q212 then
        report "PASS: Test 3 - accumulation matches Q2.12 (" & integer'image(expected_q212) & ")";
        elsif result_int = expected_q16 then
            report "FAIL: Test 3 - accumulation in Q1.6 (" & integer'image(expected_q16) & ")";
        else
            report "FAIL: Test 3 - unexpected result: " & integer'image(result_int) & ", expected Q2.12=" & integer'image(expected_q212);
        end if;

        wait for CLK_PERIOD * 5;

        report "=== MAC Testbench Complete ===";
        test_done <= true;
        wait;
    end process;

end Behavioral;