library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity test_MAC_tb is
end test_MAC_tb;

architecture Behavioral of test_MAC_tb is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '0';
    signal clear   : std_logic := '0';
    signal pixel_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal weights : std_logic_vector(7 downto 0) := (others => '0');
    signal valid  : std_logic := '0';
    signal result  : std_logic_vector(15 downto 0);
    signal done    : std_logic;

    constant clk_period : time := 10 ns;

    -- Test vectors
    type int_array is array (0 to 8) of integer;
    constant WORD_vec  : int_array := (1, 2, 3, 4, 5, 6, 7, 8, 9);
    constant weight_vec : int_array := (1, 0, -1, 1, 0, -1, 1, 0, -1);


begin
    DUT: entity work.MAC
        generic map (
            width_a => 8,
            width_b => 8,
            width_p => 16
        )
        port map (
            clk     => clk,
            rst     => rst,
            pixel_in  => pixel_in,
            weights => weights,
            valid   => valid,
            clear   => clear,
            result  => result,
            done    => done
        );

    clk <= not clk after clk_period / 2;

    -- Stimulus process: drives inputs and accumulates expected result
    stimulus_proc: process
    begin
        -- Reset
        rst <= '1';
        valid <= '0';
        clear <= '0';
        wait for clk_period * 2;
        rst <= '0';
        wait for clk_period * 2;

        -- Apply 9 test vectors
        for i in 0 to 8 loop
            pixel_in  <= std_logic_vector(to_signed(WORD_vec(i), 8));
            weights   <= std_logic_vector(to_signed(weight_vec(i), 8));
            valid     <= '1';
            wait for clk_period;
            valid     <= '0';
            wait for clk_period;
        end loop;

        clear <= '1';
        wait for clk_period;
        clear <= '0';

         -- Apply 9 test vectors again to see if accumulator resets correctly 
        for i in 0 to 8 loop
            pixel_in  <= std_logic_vector(to_signed(WORD_vec(i), 8));
            weights   <= std_logic_vector(to_signed(weight_vec(i), 8));
            valid     <= '1';
            wait for clk_period;
            valid     <= '0';
            wait for clk_period;
        end loop;

        wait;
    end process stimulus_proc;

    -- Checking process: waits for done and checks result
    check_proc: process
        variable acc : integer := 0;
        variable i   : integer := 0;
    begin
        for i in 0 to 8 loop
            acc := acc + WORD_vec(i) * weight_vec(i);
            wait until done = '1';
            assert to_integer(signed(result)) = acc
                report "MAC result mismatch at input " & integer'image(i) & ": got " & integer'image(to_integer(signed(result))) & ", expected " & integer'image(acc)
                severity ERROR;
        end loop;
        wait;
    end process check_proc;

end Behavioral;