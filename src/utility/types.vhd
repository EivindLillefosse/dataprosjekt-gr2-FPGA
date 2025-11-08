library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package types_pkg is
    -- Constants
    constant KERNEL_SIZE_1 : integer := 3;
    constant KERNEL_NUM_1 : integer := 8;
    constant STRIDE_1       : integer := 1;
    constant IMAGE_SIZE  : integer := 28;
    constant WORD_SIZE  : integer := 8;


    -- Type definitions
    subtype WORD is STD_LOGIC_VECTOR(7 downto 0);
    subtype WORD_16 is STD_LOGIC_VECTOR(15 downto 0);

    type IMAGE_VECTOR is array (0 to KERNEL_SIZE_1-1, 0 to KERNEL_SIZE_1-1) of WORD;
    type LINE_BUFFER is array (0 to KERNEL_SIZE_1-2) of WORD;
    
    -- Unconstrained array type
    type OUTPUT_ARRAY is array (natural range <>, natural range <>) of WORD;
    type OUTPUT_ARRAY_VECTOR is array (natural range <>, natural range <>, natural range <>) of WORD;

    -- 16-bit output type for MAC results
    subtype OUTPUT_WORD is STD_LOGIC_VECTOR(15 downto 0);
    type OUTPUT_ARRAY_16 is array (natural range <>, natural range <>) of OUTPUT_WORD;
    type OUTPUT_ARRAY_VECTOR_16 is array (natural range <>, natural range <>, natural range <>) of OUTPUT_WORD;


    type WORD_ARRAY is array (natural range <>) of WORD;
    type WORD_ARRAY_16 is array (natural range <>) of OUTPUT_WORD;
end package types_pkg;