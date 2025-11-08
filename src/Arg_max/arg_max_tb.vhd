library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity arg_max_tb is
end entity arg_max_tb;

architecture tb of arg_max_tb is
  constant N : natural := 8;
  constant W : natural := 16;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal start     : std_logic := '0';
  signal data_in   : WORD_ARRAY_16(0 to N-1) := (others => (others => '0'));
  signal done      : std_logic;
  signal max_idx   : unsigned(7 downto 0);


begin

  -- instantiate DUT
  uut: entity work.arg_max
    generic map ( N_INPUTS => N, DATA_W => W, IDX_W => 8 )
    port map (
      clk => clk,
      rst => rst,
      start => start,
      data_in => data_in,
      done => done,
      max_idx => max_idx
    );

  -- clock
  clk_proc: process
  begin
    wait for 5 ns;
    clk <= not clk;
  end process;

  stim_proc: process
    -- local unconstrained array type for signed words
    type signed_arr_t is array (natural range <>) of signed(W-1 downto 0);
    variable vals : signed_arr_t(0 to N-1);
  begin
    -- reset
    wait for 20 ns;
    rst <= '0';

    -- prepare a vector with a known maximum at index 5
    vals(0) := to_signed(-100, W);
    vals(1) := to_signed(10, W);
    vals(2) := to_signed(20, W);
    vals(3) := to_signed(5, W);
    vals(4) := to_signed(15, W);
    vals(5) := to_signed(127, W); -- highest
    vals(6) := to_signed(0, W);
    vals(7) := to_signed(50, W);

    -- pack into WORD_ARRAY_16 (assign signals directly)
    for i in 0 to N-1 loop
      data_in(i) <= std_logic_vector(vals(i));
    end loop;

    -- pulse start
    wait for 10 ns;
    start <= '1';
    wait for 10 ns;
    start <= '0';

    -- wait for done
    wait until done = '1';
    wait for 10 ns;

  report "Expected max index = 5, got: " & integer'image(to_integer(max_idx)) severity note;
  -- show the winning raw value (signed Q9.6 integer)
  report "Max val (signed raw) = " & integer'image(to_integer(signed(data_in(to_integer(max_idx))))) severity note;

    -- finish
    wait for 20 ns;
    report "Testbench finished" severity note;
    wait;
  end process;

end architecture tb;
