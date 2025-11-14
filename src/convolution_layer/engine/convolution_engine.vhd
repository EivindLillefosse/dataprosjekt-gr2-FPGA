----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Convolution Engine
-- Module Name: convolution_engine - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular convolution computation engine with MAC array
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity convolution_engine is
    generic (
        NUM_FILTERS     : integer := 8;
        INPUT_CHANNELS  : integer := 1;
        MAC_DATA_WIDTH  : integer := 8;
        MAC_RESULT_WIDTH: integer := MAC_DATA_WIDTH*2
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        clear        : in  std_logic;
        compute_en   : in  std_logic;
        
        -- Input data (multi-channel input bus) - flattened to support variable widths
        pixel_data   : in  std_logic_vector(INPUT_CHANNELS * MAC_DATA_WIDTH - 1 downto 0);
        channel_index: in  integer range 0 to INPUT_CHANNELS-1;
        weight_data  : in  WORD_ARRAY(0 to NUM_FILTERS-1);
        
        -- Results
        results      : out WORD_ARRAY_32(0 to NUM_FILTERS-1);
        compute_done : out std_logic_vector(NUM_FILTERS-1 downto 0)
    );
end convolution_engine;

architecture Behavioral of convolution_engine is
    -- Internal signed types and signals to match MAC port types
    subtype signed_word is signed(MAC_DATA_WIDTH-1 downto 0);
    type signed_word_array is array (natural range <>) of signed(MAC_DATA_WIDTH-1 downto 0);
    subtype signed_result is signed(MAC_RESULT_WIDTH-1 downto 0);
    type signed_result_array is array (natural range <>) of signed(MAC_RESULT_WIDTH-1 downto 0);

    signal results_s    : signed_result_array(0 to NUM_FILTERS-1);
    
    -- Extract the current channel's pixel value
    signal current_pixel : std_logic_vector(MAC_DATA_WIDTH-1 downto 0);
begin

    -- Extract pixel for current channel from flattened input
    current_pixel <= pixel_data((channel_index+1)*MAC_DATA_WIDTH-1 downto channel_index*MAC_DATA_WIDTH);

    -- Generate MAC instances for each filter
    mac_gen : for i in 0 to NUM_FILTERS-1 generate
        mac_inst : entity work.MAC
            generic map (
                WIDTH_A => MAC_DATA_WIDTH,
                WIDTH_B => 8, -- Weights are 8 bits
                WIDTH_P => MAC_RESULT_WIDTH
            )
            port map (
                clk      => clk,
                clear    => clear,
                start    => compute_en,
                pixel_in => signed(current_pixel),
                weights  => signed(weight_data(i)),
                done     => compute_done(i),
                result   => results_s(i)
            );
    end generate;

    -- Convert signed results back to std_logic_vector outputs
    result_conv : for i in 0 to NUM_FILTERS-1 generate
        results(i) <= std_logic_vector(results_s(i));
    end generate;

end Behavioral;