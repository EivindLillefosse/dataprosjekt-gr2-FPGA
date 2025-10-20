----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: Multiplier
-- Module Name: MAC - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

Library UNISIM;
use UNISIM.vcomponents.all;

Library UNIMACRO;
use UNIMACRO.vcomponents.all;

entity MAC is
   generic (
      width_a : integer := 8;
      width_b : integer := 8;
      width_p : integer := 16
   );
   Port (
       clk      : in  STD_LOGIC;
       rst      : in  STD_LOGIC;
       pixel_in : in  STD_LOGIC_VECTOR (width_a-1 downto 0);
       weights  : in  STD_LOGIC_VECTOR (width_b-1 downto 0);
       valid    : in  STD_LOGIC;
       clear    : in  STD_LOGIC;
       result   : out STD_LOGIC_VECTOR (width_p-1 downto 0);
       done     : out STD_LOGIC  
       );
end MAC;

architecture Behavioral of MAC is
   signal macc_result : std_logic_vector(width_p-1 downto 0);
   signal macc_result_prev : std_logic_vector(width_p-1 downto 0);
   signal valid_d : std_logic := '0';
   signal valid_d2 : std_logic := '0';
   signal valid_d3 : std_logic := '0';
   signal valid_d4 : std_logic := '0';
    -- Extended valid signal to cover the entire transaction
   signal valid_extended : std_logic := '0';
   signal output_changed : std_logic := '0';
   signal timeout_done : std_logic := '0';

   signal temp_ce : std_logic;
   -- internal done signal (avoid reading/writing the 'out' port 'done' inside the process)
   signal done_internal : std_logic := '0';
   signal done_next : std_logic := '0';

begin
   process(clk)
   begin
      if rising_edge(clk) then
         if rst = '1' or clear = '1' then
            valid_extended <= '0';
            valid_d <= '0';
            valid_d2 <= '0';
            valid_d3 <= '0';
            macc_result_prev <= (others => '0');
         else
            valid_d  <= valid;
            valid_d2 <= valid_d;
            valid_d3 <= valid_d2;
            valid_d4 <= valid_d3;
            macc_result_prev <= macc_result;
            if valid = '1' then
               valid_extended <= '1';
            end if;

            if valid = '1' then
               valid_extended <= '1';
            end if;

            -- If done_internal from previous cycle is high, clear transaction flags
            if done_internal = '1' then
               valid_extended <= '0';
               valid_d3 <= '0';
               valid_d2 <= '0';
               valid_d <= '0';
            end if;

         end if;
      end if;
   end process;

   -- Combinatorial output change detection (reacts immediately)
   output_changed <= '1' when (macc_result /= macc_result_prev) else '0';
   
   -- Timeout after 3 cycles (2 extra cycles)
   timeout_done <= valid_d4;
   
   -- Done when either output changes or timeout (combinational next value)
   done_internal <= output_changed or timeout_done;

   -- CE: enable when transaction active and not done
   temp_ce <= valid_extended and not done_internal;

   MACC_MACRO_inst : MACC_MACRO
   generic map (
      DEVICE => "7SERIES",
      LATENCY => 1,
      WIDTH_A => width_a,
      WIDTH_B => width_b,
      WIDTH_P => width_p)
   port map (
      P         => macc_result,
      A         => pixel_in,
      ADDSUB    => '1',           -- Always add
      B         => weights,
      CARRYIN   => '0',           -- No carry
      CE        => temp_ce, -- CE low when done is high
      CLK       => clk,
      LOAD      => '0',           -- Never load
      LOAD_DATA => (others => '0'),
      RST       => clear or rst   -- Reset on clear or rst
   );

   result <= macc_result;

      -- Drive the output port from the internal registered done signal
      done <= done_internal;

end Behavioral;