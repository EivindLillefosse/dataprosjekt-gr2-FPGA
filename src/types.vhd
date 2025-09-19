library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package types_pkg is
    -- Constants
    constant KERNEL_SIZE_1 : integer := 3;
    constant KERNEL_NUM_1 : integer := 8;
    constant STRIDE_1       : integer := 1;
    constant IMAGE_SIZE  : integer := 28;


    -- Type definitions
    subtype PIXEL is STD_LOGIC_VECTOR(7 downto 0);
    type IMAGE_VECTOR is array (0 to KERNEL_SIZE_1-1, 0 to KERNEL_SIZE_1-1) of PIXEL;
    type LINE_BUFFER is array (0 to KERNEL_SIZE_1-2) of PIXEL;
    
    -- Unconstrained array type
    type OUTPUT_ARRAY is array (natural range <>, natural range <>, natural range <>) of PIXEL;

end package types_pkg;