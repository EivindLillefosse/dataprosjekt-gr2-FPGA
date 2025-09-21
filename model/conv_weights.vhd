-- Auto-generated convolution weights for VHDL
-- Weight array initialization for conv_layer

-- Weight array declaration (add to your architecture):
signal weight_array : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1,
                                          0 to KERNEL_SIZE-1,
                                          0 to KERNEL_SIZE-1) := (
    -- Filter 0
    0 => (
        0 => (x"5A", x"13", x"5C"),
        1 => (x"EB", x"1D", x"61"),
        2 => (x"9B", x"81", x"F1")
    ),
    -- Filter 1
    1 => (
        0 => (x"F0", x"E9", x"32"),
        1 => (x"E4", x"15", x"51"),
        2 => (x"67", x"E8", x"08")
    ),
    -- Filter 2
    2 => (
        0 => (x"DF", x"12", x"64"),
        1 => (x"BE", x"DD", x"5F"),
        2 => (x"FB", x"D2", x"30")
    ),
    -- Filter 3
    3 => (
        0 => (x"D0", x"9D", x"E0"),
        1 => (x"F7", x"C7", x"FE"),
        2 => (x"70", x"34", x"51")
    ),
    -- Filter 4
    4 => (
        0 => (x"1C", x"73", x"5C"),
        1 => (x"34", x"1D", x"E9"),
        2 => (x"34", x"4A", x"B8")
    ),
    -- Filter 5
    5 => (
        0 => (x"DA", x"B6", x"A6"),
        1 => (x"FB", x"3D", x"64"),
        2 => (x"37", x"3B", x"5C")
    ),
    -- Filter 6
    6 => (
        0 => (x"E6", x"2E", x"F8"),
        1 => (x"ED", x"E5", x"BB"),
        2 => (x"FF", x"DD", x"00")
    ),
    -- Filter 7
    7 => (
        0 => (x"2A", x"27", x"99"),
        1 => (x"21", x"9A", x"31"),
        2 => (x"B6", x"DC", x"59")
    )
);

-- Bias array declaration:
signal bias_array : WORD_ARRAY(0 to NUM_FILTERS-1) := (
    0 => x"00",
    1 => x"06",
    2 => x"00",
    3 => x"0F",
    4 => x"00",
    5 => x"01",
    6 => x"29",
    7 => x"13"
);
