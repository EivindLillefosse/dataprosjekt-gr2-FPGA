library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package bias_pkg is
    type layer_0_conv2d_t is array(0 to 7) of signed(15 downto 0);
    constant layer_0_conv2d_BIAS : layer_0_conv2d_t := (
        0 => to_signed(0, 16),
        1 => to_signed(2, 16),
        2 => to_signed(2, 16),
        3 => to_signed(1, 16),
        4 => to_signed(0, 16),
        5 => to_signed(-1, 16),
        6 => to_signed(0, 16),
        7 => to_signed(1, 16)
    );
    type layer_2_conv2d_1_t is array(0 to 15) of signed(15 downto 0);
    constant layer_2_conv2d_1_BIAS : layer_2_conv2d_1_t := (
        0 => to_signed(9, 16),
        1 => to_signed(-2, 16),
        2 => to_signed(-2, 16),
        3 => to_signed(-1, 16),
        4 => to_signed(-2, 16),
        5 => to_signed(-2, 16),
        6 => to_signed(-1, 16),
        7 => to_signed(-3, 16),
        8 => to_signed(-3, 16),
        9 => to_signed(0, 16),
        10 => to_signed(-1, 16),
        11 => to_signed(1, 16),
        12 => to_signed(-3, 16),
        13 => to_signed(1, 16),
        14 => to_signed(-2, 16),
        15 => to_signed(-4, 16)
    );
    type layer_5_dense_t is array(0 to 63) of signed(15 downto 0);
    constant layer_5_dense_BIAS : layer_5_dense_t := (
        0 => to_signed(-1, 16),
        1 => to_signed(3, 16),
        2 => to_signed(5, 16),
        3 => to_signed(0, 16),
        4 => to_signed(4, 16),
        5 => to_signed(-2, 16),
        6 => to_signed(-1, 16),
        7 => to_signed(1, 16),
        8 => to_signed(4, 16),
        9 => to_signed(1, 16),
        10 => to_signed(-2, 16),
        11 => to_signed(1, 16),
        12 => to_signed(-1, 16),
        13 => to_signed(-1, 16),
        14 => to_signed(3, 16),
        15 => to_signed(4, 16),
        16 => to_signed(1, 16),
        17 => to_signed(-1, 16),
        18 => to_signed(-6, 16),
        19 => to_signed(2, 16),
        20 => to_signed(-2, 16),
        21 => to_signed(0, 16),
        22 => to_signed(-1, 16),
        23 => to_signed(-2, 16),
        24 => to_signed(1, 16),
        25 => to_signed(0, 16),
        26 => to_signed(2, 16),
        27 => to_signed(-1, 16),
        28 => to_signed(-1, 16),
        29 => to_signed(0, 16),
        30 => to_signed(2, 16),
        31 => to_signed(4, 16),
        32 => to_signed(5, 16),
        33 => to_signed(-2, 16),
        34 => to_signed(3, 16),
        35 => to_signed(-2, 16),
        36 => to_signed(2, 16),
        37 => to_signed(-1, 16),
        38 => to_signed(1, 16),
        39 => to_signed(1, 16),
        40 => to_signed(-1, 16),
        41 => to_signed(1, 16),
        42 => to_signed(2, 16),
        43 => to_signed(2, 16),
        44 => to_signed(0, 16),
        45 => to_signed(-1, 16),
        46 => to_signed(-1, 16),
        47 => to_signed(-1, 16),
        48 => to_signed(1, 16),
        49 => to_signed(2, 16),
        50 => to_signed(-2, 16),
        51 => to_signed(1, 16),
        52 => to_signed(-1, 16),
        53 => to_signed(0, 16),
        54 => to_signed(2, 16),
        55 => to_signed(-3, 16),
        56 => to_signed(-3, 16),
        57 => to_signed(-1, 16),
        58 => to_signed(-1, 16),
        59 => to_signed(4, 16),
        60 => to_signed(-2, 16),
        61 => to_signed(3, 16),
        62 => to_signed(-1, 16),
        63 => to_signed(0, 16)
    );
    type layer_6_dense_1_t is array(0 to 9) of signed(15 downto 0);
    constant layer_6_dense_1_BIAS : layer_6_dense_1_t := (
        0 => to_signed(-3, 16),
        1 => to_signed(-2, 16),
        2 => to_signed(3, 16),
        3 => to_signed(4, 16),
        4 => to_signed(1, 16),
        5 => to_signed(1, 16),
        6 => to_signed(-5, 16),
        7 => to_signed(3, 16),
        8 => to_signed(-1, 16),
        9 => to_signed(-2, 16)
    );
end package bias_pkg;

package body bias_pkg is
end package body bias_pkg;
