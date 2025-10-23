----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: Multiplier and Accumulate Unit
-- Module Name: MAC - RTL
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.02 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MAC is
   generic (
      WIDTH_A : integer := 8;
      WIDTH_B : integer := 8;
      WIDTH_P : integer := 16
   );
   Port (
       clk, load, ce, clear  : in  STD_LOGIC;
       pixel_in              : in  signed (WIDTH_A-1 downto 0);
       weights               : in  signed (WIDTH_B-1 downto 0);
       result                : out signed (WIDTH_P-1 downto 0)
       );
end MAC;

architecture RTL of MAC is
   signal reg_pixel_in   : signed(WIDTH_A-1 downto 0);
   signal reg_weights    : signed(WIDTH_B-1 downto 0);
   -- register controlling accumulator clear (sload_reg in UG901 example)
   signal reg_load       : STD_LOGIC := '0';
   signal reg_mult       : signed((WIDTH_A+WIDTH_B)-1 downto 0);
   signal adder_out      : signed(WIDTH_P-1 downto 0);
   signal old_result     : signed(WIDTH_P-1 downto 0);

begin
   process(adder_out, reg_load)
   begin
      if reg_load = '1' then
         old_result <= (others => '0');
      else
         old_result <= adder_out;
      end if;
   end process;

   process(clk)
   begin
      if rising_edge(clk) then
         if clear = '1' then
            -- synchronous clear: reset operand registers and indicate clear to combinational driver
            reg_pixel_in    <= (others => '0');
            reg_weights     <= (others => '0');
            reg_mult        <= (others => '0');
            reg_load        <= '1';
            adder_out       <= (others => '0');
         else
            if ce = '1' then
               -- sample inputs into registers
               reg_pixel_in <= pixel_in;
               reg_weights  <= weights;
               -- multiplier uses previously registered operands (pipelined)
               reg_mult <= reg_pixel_in * reg_weights;
               -- capture load (synchronous)
               reg_load <= load;
               -- compute next adder output; old_result is supplied by combinational process
               adder_out <= old_result + reg_mult;
            end if;
         end if;
      end if;
   end process;

   -- Output the result
   result <= adder_out;

end RTL;