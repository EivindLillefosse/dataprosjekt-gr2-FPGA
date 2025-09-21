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
       done     : out STD_LOGIC  -- Added done signal
   );

end MAC;

architecture Behavioral of MAC is
   signal macc_p             : std_logic_vector(width_p-1 downto 0);
   signal addsb, carryin, ce : std_logic := '0';
   signal load_data          : std_logic_vector(width_p-1 downto 0) := (others => '0'); 
   signal load               : std_logic := '0';  
   signal valid_d            : std_logic := '0';
   -- MACC_MACRO: Multiple Accumulate Function implemented in a DSP48E
   --             Artix-7
   -- Xilinx HDL Language Template, version 2024.1
begin
   addsb <= '1';
   process(clk)
   begin
      if rising_edge(clk) then
         if rst = '1' then
            valid_d <= '0';
         else
            valid_d <= valid;
            load_data <= macc_p;
            done <= valid_d;
         end if;
      end if;
   end process;

   ce <= valid or valid_d;
   load <= valid and not valid_d;

   MACC_MACRO_inst : MACC_MACRO
   generic map (
      DEVICE => "7SERIES",  -- Target Device: "VIRTEX5", "7SERIES", "SPARTAN6" 
      LATENCY => 1,         -- Desired clock cycle latency, 1-4
      WIDTH_A => width_a,        -- Multiplier A-input bus width, 1-25
      WIDTH_B => width_b,        -- Multiplier B-input bus width, 1-18     
      WIDTH_P => width_p)        -- Accumulator output bus width, 1-48
   port map (
      P         => macc_p,     -- MACC ouput bus, width determined by WIDTH_P generic 
      A         => pixel_in,     -- MACC input A bus, width determined by WIDTH_A generic 
      ADDSUB    => addsb, -- 1-bit add/sub input, high selects add, low selects subtract
      B         => weights,           -- MACC input B bus, width determined by WIDTH_B generic 
      CARRYIN   => carryin, -- 1-bit carry-in input to accumulator
      CE        => '1',      -- 1-bit active high input clock enable
      CLK       => clk,    -- 1-bit positive edge clock input
      LOAD      => '1', -- 1-bit active high input load accumulator enable
      LOAD_DATA => load_data, -- Load accumulator input data, 
                              -- width determined by WIDTH_P generic
      RST       => clear or rst    -- 1-bit input active high reset

   );
   result    <= macc_p;

end Behavioral;
