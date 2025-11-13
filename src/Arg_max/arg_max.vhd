----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 08.11.2025
-- Design Name: Argmax Module
-- Module Name: arg_max - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Finds the index of the maximum signed input among N inputs.
--              Inputs are provided packed MSB..LSB as: [ (N_INPUTS-1) | ... | 0 ]
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity arg_max is
  generic (
    N_INPUTS  : natural := 10;    -- number of inputs to compare
    DATA_W    : natural := 16;   -- width of each input word
    IDX_W     : natural := 8      -- width of index output
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    start     : in  std_logic; -- pulse to start one comparison round
    data_in   : in  WORD_ARRAY_16(0 to N_INPUTS-1); -- array of signed words
    done      : out std_logic; -- asserted one cycle when result ready
    max_idx   : out unsigned(IDX_W-1 downto 0) -- index of the maximum value
  );
end entity arg_max;

architecture Behavioral of arg_max is
  -- internal counters/flags
  signal cur_idx  : integer range 0 to N_INPUTS := 0;
  signal best_idx : integer range 0 to N_INPUTS-1 := 0;

  -- store values as signed 16-bit (matches OUTPUT_WORD / WORD_ARRAY_16)
  signal best_val : signed(DATA_W-1 downto 0) := (others => '0');
  signal running  : std_logic := '0';
begin

  process(clk)
    variable cur_val : signed(DATA_W-1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cur_idx <= 0;
        best_idx <= 0;
        best_val <= (others => '0');
        running <= '0';
        done <= '0';
        max_idx <= (others => '0');
      else
        done <= '0';
        if start = '1' and running = '0' then
          -- start a new round: take element 0 as initial best
          best_idx <= 0;
          best_val <= signed(data_in(0));
          cur_idx <= 1;
          running <= '1';
        elsif running = '1' then
          if cur_idx < N_INPUTS then
            cur_val := signed(data_in(cur_idx));
            if cur_val > best_val then
              best_val <= cur_val;
              best_idx <= cur_idx;
            end if;
            cur_idx <= cur_idx + 1;
          else
            -- finished
            running <= '0';
            done <= '1';
            -- present outputs
            max_idx <= to_unsigned(best_idx, IDX_W);
            cur_idx <= 0;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture Behavioral;
