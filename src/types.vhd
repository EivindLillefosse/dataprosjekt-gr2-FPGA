library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package types_pkg is
    -- Constants
    constant KERNEL_SIZE : integer := 3;

    -- Type definitions
    subtype PIXEL is STD_LOGIC_VECTOR(7 downto 0);
    type IMAGE_VECTOR is array (0 to KERNEL_SIZE-1, 0 to KERNEL_SIZE-1) of PIXEL;
    type LINE_BUFFER is array (0 to KERNEL_SIZE-2) of PIXEL;

end package types_pkg;