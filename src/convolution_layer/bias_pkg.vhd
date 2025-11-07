library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package bias_pkg is
    type layer_0_conv2d_t is array(0 to 7) of signed(7 downto 0);
    constant layer_0_conv2d_BIAS : layer_0_conv2d_t := (
        0 => to_signed(-1, 8),
        1 => to_signed(0, 8),
        2 => to_signed(-1, 8),
        3 => to_signed(-2, 8),
        4 => to_signed(0, 8),
        5 => to_signed(-1, 8),
        6 => to_signed(-1, 8),
        7 => to_signed(-1, 8)
    );
    type layer_2_conv2d_1_t is array(0 to 15) of signed(7 downto 0);
    constant layer_2_conv2d_1_BIAS : layer_2_conv2d_1_t := (
        0 => to_signed(1, 8),
        1 => to_signed(-1, 8),
        2 => to_signed(3, 8),
        3 => to_signed(1, 8),
        4 => to_signed(-2, 8),
        5 => to_signed(-1, 8),
        6 => to_signed(-1, 8),
        7 => to_signed(0, 8),
        8 => to_signed(-1, 8),
        9 => to_signed(-1, 8),
        10 => to_signed(2, 8),
        11 => to_signed(-1, 8),
        12 => to_signed(0, 8),
        13 => to_signed(-1, 8),
        14 => to_signed(-2, 8),
        15 => to_signed(0, 8)
    );
    type layer_5_dense_t is array(0 to 63) of signed(7 downto 0);
    constant layer_5_dense_BIAS : layer_5_dense_t := (
        0 => to_signed(0, 8),
        1 => to_signed(-1, 8),
        2 => to_signed(-2, 8),
        3 => to_signed(-1, 8),
        4 => to_signed(-1, 8),
        5 => to_signed(-1, 8),
        6 => to_signed(0, 8),
        7 => to_signed(-1, 8),
        8 => to_signed(-2, 8),
        9 => to_signed(-1, 8),
        10 => to_signed(0, 8),
        11 => to_signed(-1, 8),
        12 => to_signed(-1, 8),
        13 => to_signed(-1, 8),
        14 => to_signed(0, 8),
        15 => to_signed(-1, 8),
        16 => to_signed(-1, 8),
        17 => to_signed(-1, 8),
        18 => to_signed(-1, 8),
        19 => to_signed(-1, 8),
        20 => to_signed(-1, 8),
        21 => to_signed(-1, 8),
        22 => to_signed(-1, 8),
        23 => to_signed(-1, 8),
        24 => to_signed(-1, 8),
        25 => to_signed(-1, 8),
        26 => to_signed(-1, 8),
        27 => to_signed(0, 8),
        28 => to_signed(-1, 8),
        29 => to_signed(-1, 8),
        30 => to_signed(-1, 8),
        31 => to_signed(-1, 8),
        32 => to_signed(1, 8),
        33 => to_signed(-1, 8),
        34 => to_signed(0, 8),
        35 => to_signed(0, 8),
        36 => to_signed(-1, 8),
        37 => to_signed(-1, 8),
        38 => to_signed(0, 8),
        39 => to_signed(-1, 8),
        40 => to_signed(-1, 8),
        41 => to_signed(-1, 8),
        42 => to_signed(-1, 8),
        43 => to_signed(0, 8),
        44 => to_signed(0, 8),
        45 => to_signed(-1, 8),
        46 => to_signed(-1, 8),
        47 => to_signed(-1, 8),
        48 => to_signed(0, 8),
        49 => to_signed(-1, 8),
        50 => to_signed(-1, 8),
        51 => to_signed(-1, 8),
        52 => to_signed(0, 8),
        53 => to_signed(-1, 8),
        54 => to_signed(-1, 8),
        55 => to_signed(-1, 8),
        56 => to_signed(0, 8),
        57 => to_signed(0, 8),
        58 => to_signed(-1, 8),
        59 => to_signed(-1, 8),
        60 => to_signed(-1, 8),
        61 => to_signed(-1, 8),
        62 => to_signed(-1, 8),
        63 => to_signed(-2, 8)
    );
    type layer_6_dense_1_t is array(0 to 9) of signed(7 downto 0);
    constant layer_6_dense_1_BIAS : layer_6_dense_1_t := (
        0 => to_signed(11, 8),
        1 => to_signed(1, 8),
        2 => to_signed(-12, 8),
        3 => to_signed(6, 8),
        4 => to_signed(0, 8),
        5 => to_signed(-8, 8),
        6 => to_signed(2, 8),
        7 => to_signed(-11, 8),
        8 => to_signed(1, 8),
        9 => to_signed(7, 8)
    );
end package bias_pkg;

package body bias_pkg is
end package body bias_pkg;
