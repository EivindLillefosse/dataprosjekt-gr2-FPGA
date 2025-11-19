-- Simple testbench for SPI_SLAVE continuous retransmit behavior
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_slave_tb is
end entity;

architecture tb of spi_slave_tb is
  constant CLK_PERIOD : time := 10 ns; -- 100 MHz
  constant SCLK_HALF_PERIOD : time := 20 ns; -- SCLK period 40 ns

  signal CLK    : std_logic := '0';
  signal RESET  : std_logic := '1';
  signal SCLK   : std_logic := '0';
  signal CS_N   : std_logic := '1';
  signal MOSI   : std_logic := '0';
  signal MISO   : std_logic;

  signal DATA_IN      : std_logic_vector(7 downto 0) := x"FE";
  signal DATA_IN_VALID: std_logic := '0';
  signal DATA_IN_READY: std_logic;
  signal DATA_OUT     : std_logic_vector(7 downto 0);
  signal DATA_OUT_VALID: std_logic;

  -- master-side receiver to sample MISO and reconstruct bytes
  signal master_shift : std_logic_vector(7 downto 0) := (others => '0');

begin
  -- instantiate DUT
  dut: entity work.SPI_SLAVE(RTL)
    port map(
      CLK => CLK,
      RESET => RESET,
      SCLK => SCLK,
      CS_N => CS_N,
      MOSI => MOSI,
      MISO => MISO,
      DATA_IN => DATA_IN,
      DATA_IN_VALID => DATA_IN_VALID,
      DATA_IN_READY => DATA_IN_READY,
      DATA_OUT => DATA_OUT,
      DATA_OUT_VALID => DATA_OUT_VALID
    );

  -- system clock
  clk_proc: process
  begin
    while now < 10 ms loop
      CLK <= '0';
      wait for CLK_PERIOD/2;
      CLK <= '1';
      wait for CLK_PERIOD/2;
    end loop;
    wait;
  end process;

  -- initial stimulus
  stim_proc: process
  begin
    -- reset
    RESET <= '1';
    CS_N <= '1';
    DATA_IN <= x"FE"; -- 11111110
    wait for 100 ns;
    RESET <= '0';

    -- host writes DATA_IN while CS_N high so DUT can load initial byte
    wait for 100 ns;

    -- lower CS_N to start SPI traffic
    CS_N <= '0';
    wait for 10 ns;

    -- start toggling SCLK for several bytes
    -- we'll toggle SCLK in a separate process; here, after a few bytes, change DATA_IN
    wait for 40 * SCLK_HALF_PERIOD; -- 40 SCLK edges (approx 10 bytes)

    -- while still CS_N low, change DATA_IN. DUT should only start transmitting
    -- the new value after the current byte boundary.
    report "Changing DATA_IN to 0xA5 while CS_N remains low";
    DATA_IN <= x"A5";

    wait for 40 * SCLK_HALF_PERIOD; -- collect more bytes

    -- finish
    report "Testbench finished";
    wait for 100 ns;
    std.env.stop(0);
    wait;
  end process;

  -- SCLK generator (continuous once CS_N low)
  sclk_proc: process
  begin
    wait until CS_N = '0';
    -- run for a while
    for i in 0 to 199 loop
      SCLK <= '0';
      wait for SCLK_HALF_PERIOD;
      SCLK <= '1';
      wait for SCLK_HALF_PERIOD;
    end loop;
    wait;
  end process;

  -- master receiver: sample MISO on SCLK rising edge and assemble bytes
  master_recv: process
    variable v_shift : std_logic_vector(7 downto 0) := (others => '0');
    variable v_cnt   : integer := 0;
  begin
    wait until CS_N = '0';
    loop
      wait until rising_edge(SCLK);
      -- small delay to allow DUT to drive MISO (synchronizers introduce delays)
      wait for 5 ns;
      v_shift := v_shift(6 downto 0) & MISO;
      if v_cnt = 7 then
        -- full byte assembled (MSB-first)
        report "Master received byte: 0x" & to_hstring(unsigned(v_shift)) severity note;
        v_cnt := 0;
        v_shift := (others => '0');
      else
        v_cnt := v_cnt + 1;
      end if;
    end loop;
  end process;

end architecture tb;
