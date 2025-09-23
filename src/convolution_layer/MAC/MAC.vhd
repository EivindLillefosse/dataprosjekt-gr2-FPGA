----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: Multiplier
-- Module Name: top - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

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
   signal carryin, ce        : std_logic := '0';
   signal addsb              : std_logic := '1';
   signal load_data          : std_logic_vector(width_p-1 downto 0) := (others => '0'); 
   signal load               : std_logic := '0';  
   signal rst_combined       : std_logic; -- Intermediate signal for combined reset
   signal macc_result        : std_logic_vector(width_p-1 downto 0); -- Intermediate signal for MACC_MACRO output
   signal changed_pulse_internal : std_logic; -- Intermediate signal for changed_pulse
   signal calc_done         : std_logic; -- Intermediate signal for done logic

begin
   process(clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            calc_done <= '0';
         else
            if valid = '1' and (pixel_in = (width_a-1 downto 0 => '0') or weights = (width_b-1 downto 0 => '0')) then
               calc_done <= '1';
            else
               calc_done <= '0';
            end if;
         end if;
      end if;
   end process;

   load <= valid and not (calc_done or changed_pulse_internal);

   -- Combine clear and rst signals
   rst_combined <= clear or rst;

   WORD_change_inst : entity work.change_detect_bus
     generic map (
       W => width_p -- Corrected generic name
     )
     port map (
       clk => clk,
       rst => rst,
       word_in => macc_result,
       changed_pulse => changed_pulse_internal -- Use intermediate signal
     );

   -- Assign intermediate signal to done
   done <= calc_done or changed_pulse_internal;

   MACC_MACRO_inst : MACC_MACRO
   generic map (
      DEVICE => "7SERIES",  -- Target Device: "VIRTEX5", "7SERIES", "SPARTAN6" 
      LATENCY => 1,         -- Desired clock cycle latency, 1-4
      WIDTH_A => width_a,        -- Multiplier A-input bus width, 1-25
      WIDTH_B => width_b,        -- Multiplier B-input bus width, 1-18     
      WIDTH_P => width_p)        -- Accumulator output bus width, 1-48
   port map (
      P         => macc_result,     -- Connect intermediate signal
      A         => pixel_in,     -- MACC input A bus, width determined by WIDTH_A generic 
      ADDSUB    => addsb, -- 1-bit add/sub input, high selects add, low selects subtract
      B         => weights,           -- MACC input B bus, width determined by WIDTH_B generic 
      CARRYIN   => carryin, -- 1-bit carry-in input to accumulator
      CE        => load,      -- 1-bit active high input clock enable
      CLK       => clk,    -- 1-bit positive edge clock input
      LOAD      => '0', -- 1-bit active high input load accumulator enable
      LOAD_DATA => load_data, -- Load accumulator input data, 
                              -- width determined by WIDTH_P generic
      RST       => rst_combined    -- 1-bit input active high reset

   );

   -- Assign intermediate signal to result
   result <= macc_result;

end Behavioral;
