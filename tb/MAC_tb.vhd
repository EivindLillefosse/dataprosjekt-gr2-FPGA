library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity test_MAC_tb is
end test_MAC_tb;

architecture Behavioral of test_MAC_tb is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '0';
    signal pixels  : std_logic_vector(7 downto 0) := (others => '0');
    signal weights : std_logic_vector(7 downto 0) := (others => '0');
    signal valid  : std_logic := '0';
    signal result  : std_logic_vector(15 downto 0);

    constant clk_period : time := 10 ns;

    component MAC is
    generic (
        WIDTH_A : integer := 8;
        WIDTH_B : integer := 8;
        WIDTH_P : integer := 16
    );
    Port (
         clk     : in  STD_LOGIC;
         rst     : in  STD_LOGIC;
         pixels  : in  STD_LOGIC_VECTOR (WIDTH_A-1 downto 0);
         weights : in  STD_LOGIC_VECTOR (WIDTH_B-1 downto 0);
         valid  : in  STD_LOGIC;
         result  : out STD_LOGIC_VECTOR (WIDTH_P-1 downto 0)
    );
    end component;

    -- Test vectors
    type int_array is array (0 to 8) of integer;
    constant pixel_vec  : int_array := (1, 2, 3, 4, 5, 6, 7, 8, 9);
    constant weight_vec : int_array := (1, 0, -1, 1, 0, -1, 1, 0, -1);

    -- For checking result
    signal expected_result : integer := 0;
begin
    DUT: MAC
    port map (
         clk     => clk,
         rst     => rst,
         pixels  => pixels,
         weights => weights,
         valid  => valid,
         result  => result
    );

    clk <= not clk after clk_period / 2;

    process
        variable acc : integer := 0;
    begin
        -- Reset
        rst <= '1';
        valid <= '0';
        wait for clk_period * 2;
        rst <= '0';
        wait for clk_period * 2;

        -- Apply 9 test vectors
        for i in 0 to 8 loop
            pixels  <= std_logic_vector(to_signed(pixel_vec(i), 8));
            weights <= std_logic_vector(to_signed(weight_vec(i), 8));
            valid  <= '1';
            wait for clk_period;
            valid  <= '0';
            wait for clk_period;

            -- Accumulate expected result
            acc := acc + pixel_vec(i) * weight_vec(i);
        end loop;

        wait for clk_period * 2;
        expected_result <= acc;

        -- Wait for result to settle
        wait for clk_period * 2;

        -- Check result
        assert to_integer(signed(result)) = expected_result
        report "MAC result mismatch: got " & integer'image(to_integer(signed(result))) &
               ", expected " & integer'image(expected_result)
        severity error;

        wait;
    end process;

end Behavioral;