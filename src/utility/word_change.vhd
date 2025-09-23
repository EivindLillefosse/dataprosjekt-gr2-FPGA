library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity change_detect_bus is
  generic (
    W : natural := 8
  );
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    word_in       : in  std_logic_vector(W-1 downto 0);
    changed_pulse : out std_logic
  );
end entity;

architecture rtl of change_detect_bus is
  signal prev_bus : std_logic_vector(W-1 downto 0) := (others => '0');
begin
  -- pulse high for one cycle when any bit differs
  changed_pulse <= '1' when (word_in xor prev_bus) /= (W-1 downto 0 => '0') else '0';
process(clk, rst)
  begin
    if rst = '1' then
      prev_bus <= (others => '0');
    elsif rising_edge(clk) then
      prev_bus <= word_in;
    end if;
  end process;
end architecture;