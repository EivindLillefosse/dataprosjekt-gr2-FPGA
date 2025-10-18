----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 10.18.2025
-- Design Name: Fully Connected Layer 1
-- Module Name: FC1 - Structural
-- Project Name: CNN Accelerator
-- Description: Wrapper for FC layer connecting 400 inputs to 64 outputs
--              Instantiates fc_generic with appropriate generics
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity FC1 is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        -- Input interface
        pixel_valid   : in  std_logic;                  -- Input pixel is valid
        pixel_data    : in  WORD;                       -- Input pixel value (8 bits)
        pixel_index   : in  integer range 0 to 399;     -- Position in input (0-399)
        
        -- Weight memory interface
        weight_data   : out WORD_ARRAY(0 to 63);       -- Retrieved weights for this pixel
        weight_valid  : out std_logic;                  -- Weights are valid
        weight_addr   : out std_logic_vector(14 downto 0);  -- Address to weight memory
        weight_en     : out std_logic                   -- Enable weight memory read
    );
end FC1;

architecture Structural of FC1 is

    COMPONENT fc_generic
    generic (
        NUM_INPUTS  : integer;
        NUM_OUTPUTS : integer;
        ADDR_WIDTH  : integer
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        pixel_valid   : in  std_logic;
        pixel_data    : in  WORD;
        pixel_index   : in  integer range 0 to NUM_INPUTS-1;
        weight_data   : out WORD_ARRAY(0 to NUM_OUTPUTS-1);
        weight_valid  : out std_logic;
        weight_addr   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        weight_en     : out std_logic
    );
    END COMPONENT;

begin

    -- Instantiate generic FC layer for 400 inputs -> 64 outputs
    fc1_inst : fc_generic
    generic map (
        NUM_INPUTS  => 400,
        NUM_OUTPUTS => 64,
        ADDR_WIDTH  => 15
    )
    port map (
        clk         => clk,
        rst         => rst,
        pixel_valid => pixel_valid,
        pixel_data  => pixel_data,
        pixel_index => pixel_index,
        weight_data => weight_data,
        weight_valid => weight_valid,
        weight_addr => weight_addr,
        weight_en   => weight_en
    );

end Structural;
   