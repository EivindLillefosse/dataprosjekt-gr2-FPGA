-- Auto-generated convolution weights for VHDL
-- Weight array initialization for conv_layer

-- Weight array declaration (add to your architecture):
signal weight_array : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1,
                                          0 to KERNEL_SIZE-1,
                                          0 to KERNEL_SIZE-1) := (
    -- Filter 0
    0 => (
        0 => (x"1B", x"DB", x"7F"),
        1 => (x"BF", x"E6", x"EA"),
        2 => (x"99", x"D4", x"60")
    ),
    -- Filter 1
    1 => (
        0 => (x"64", x"3D", x"68"),
        1 => (x"70", x"3B", x"BF"),
        2 => (x"38", x"53", x"01")
    ),
    -- Filter 2
    2 => (
        0 => (x"49", x"63", x"33"),
        1 => (x"FC", x"AF", x"A8"),
        2 => (x"A1", x"F1", x"0C")
    ),
    -- Filter 3
    3 => (
        0 => (x"47", x"5A", x"CE"),
        1 => (x"5D", x"00", x"63"),
        2 => (x"2E", x"2B", x"1A")
    ),
    -- Filter 4
    4 => (
        0 => (x"49", x"C7", x"FA"),
        1 => (x"0C", x"6B", x"F6"),
        2 => (x"35", x"48", x"D9")
    ),
    -- Filter 5
    5 => (
        0 => (x"AF", x"BB", x"1E"),
        1 => (x"37", x"CB", x"9E"),
        2 => (x"65", x"05", x"F8")
    ),
    -- Filter 6
    6 => (
        0 => (x"A2", x"A2", x"88"),
        1 => (x"32", x"D1", x"19"),
        2 => (x"50", x"4E", x"43")
    ),
    -- Filter 7
    7 => (
        0 => (x"CC", x"61", x"F3"),
        1 => (x"BB", x"4F", x"5A"),
        2 => (x"FD", x"53", x"EC")
    )
);

-- Bias array declaration:
signal bias_array : WORD_ARRAY(0 to NUM_FILTERS-1) := (
    0 => x"00",
    1 => x"00",
    2 => x"09",
    3 => x"FF",
    4 => x"07",
    5 => x"24",
    6 => x"12",
    7 => x"00"
);
