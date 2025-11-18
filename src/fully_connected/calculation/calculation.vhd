----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Nikolai Sandvik Nore
-- 
-- Create Date: 05.10.2025
-- Design Name: Fully Connected Calculation Module
-- Module Name: calculation - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular fully connected computation engine with MAC array
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity calculation is
    generic (
        NODES             : integer := 64;
        MAC_DATA_WIDTH    : integer := 16;
        MAC_RESULT_WIDTH  : integer := 32
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        clear        : in  std_logic;
        -- Input data
        pixel_data   : in  WORD_16;
        weight_data  : in  WORD_ARRAY(0 to NODES-1);
        compute_en   : in  std_logic;
        -- Results
        results      : out WORD_ARRAY_32(0 to NODES-1);
        compute_done : out std_logic_vector(NODES-1 downto 0)
    );
end calculation;

architecture Structural of calculation is

    -- MAC.result is a signed vector; declare a local signed-array type so
    -- we can connect the MAC result port directly without casting issues.
    type signed_result_array_t is array (natural range <>) of signed(MAC_RESULT_WIDTH-1 downto 0);
    signal mac_results : signed_result_array_t(0 to NODES-1);

begin

    -- Generate MAC instances for each filter
    mac_gen : for i in 0 to NODES-1 generate
        mac_inst : entity work.MAC
            generic map (
                WIDTH_A => MAC_DATA_WIDTH,
                WIDTH_B => 8,
                WIDTH_P => MAC_RESULT_WIDTH
            )
            port map (
                clk      => clk,
                start    => compute_en,
                clear    => clear,
                
                pixel_in => signed(pixel_data),
                weights  => signed(weight_data(i)),
                done     => compute_done(i),
                result   => mac_results(i)
            );

        -- Convert signed MAC output to std_logic_vector for output port
        results(i) <= std_logic_vector(mac_results(i));
    end generate;

end Structural;