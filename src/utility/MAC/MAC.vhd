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
-- The MAC unit performs a multiply-accumulate operation over multiple clock cycles.
-- Start it by pulsing 'start'. The multiplication takes 1 cycle, and accumulation takes another cycle.
-- When the MAC is done with the operation, it pulses 'done' high for 1 cycle.
-- Clear the accumulator by pulsing 'clear' high for 1 cycle.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MAC is
   generic (
      USE_CONTROLLER : boolean := false;
      WIDTH_A : integer := 8;
      WIDTH_B : integer := 8;
      WIDTH_P : integer := 16
   );
   Port (
      clk                : in  STD_LOGIC;
      start              : in  STD_LOGIC := '0';
      clear              : in  STD_LOGIC := '0';
      pixel_in           : in  signed (WIDTH_A-1 downto 0);
      weights            : in  signed (WIDTH_B-1 downto 0);
      done               : out STD_LOGIC := '0';
      result             : out signed (WIDTH_P-1 downto 0)
      );
end MAC;

architecture RTL of MAC is
   signal reg_pixel_in   : signed(WIDTH_A-1 downto 0) := (others => '0');
   signal reg_weights    : signed(WIDTH_B-1 downto 0) := (others => '0');
   signal reg_mult       : signed((WIDTH_A+WIDTH_B)-1 downto 0) := (others => '0');
   signal adder_out      : signed(WIDTH_P-1 downto 0) := (others => '0');
   signal old_result     : signed(WIDTH_P-1 downto 0) := (others => '0');
   signal running        : STD_LOGIC := '0';
   signal reg_load       : std_logic := '0';
   signal cycle_count    : integer range 0 to 3 := 0;

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
         -- Always sample clear signal
         reg_load <= clear;
         
         -- default: done is low unless set later in this clock
         done <= '0';
         
         -- Clear adder_out when clear is asserted
         if clear = '1' then
            adder_out <= (others => '0');
         end if;
         
         if start = '1' then
            running <= '1';
            done <= '0';
            cycle_count <= 0;
         end if;
         
         if running = '1' then
            cycle_count <= cycle_count + 1;
            
            case cycle_count is
               when 0 =>
                  -- Cycle 0: sample inputs into registers
                  reg_pixel_in <= pixel_in;
                  reg_weights  <= weights;
               
               when 1 =>
                  -- Cycle 1: multiply (using registered operands from cycle 0)
                  reg_mult <= reg_pixel_in * reg_weights;
               
               when 2 =>
                  -- Cycle 2: accumulate (using multiply result from cycle 1)
                  adder_out <= old_result + reg_mult;
                  running <= '0';
                  done <= '1';
               
               when others =>
                  running <= '0';
                  done <= '0';
            end case;
         end if;
      end if;
   end process;
   -- Output the result
   result <= adder_out;

end RTL;