----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: Multiplier
-- Module Name: top - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.types_pkg.all;



entity conv_layer is
    generic (
        IMAGE_SIZE : integer := 28;
        KERNEL_SIZE : integer := 3;
        INPUT_CHANNELS : integer := 1;
        NUM_FILTERS : integer := 8;
        STRIDE : integer := 1
    );
    Port ( 
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        enable : in STD_LOGIC;

        input_valid : in std_logic;  -- High when input_pixel is valid
        input_pixel : in WORD; -- 8-bit pixel input
        input_row : inout integer; -- Current row of the input pixel
        input_col : inout integer; -- Current column of the input pixel
        input_ready : out std_logic; -- High when ready for the next input

        output_valid : out std_logic; -- High when output_pixel is valid
        output_pixel : out std_logic_vector(15 downto 0); -- 16-bit output pixel
        output_row : out integer; -- Current row of the output pixel
        output_col : out integer; -- Current column of the output pixel
        output_ready : out std_logic; -- High when module is ready for next input

        layer_done : out STD_LOGIC
    );
end conv_layer;

architecture Behavioral of conv_layer is
    -- Declare signals
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
    signal weights : WORD_ARRAY(0 to NUM_FILTERS-1) := (others => (others => '0'));    
    signal valid  : std_logic := '0';
    signal done : STD_LOGIC_VECTOR(NUM_FILTERS-1 downto 0) := (others => '0');    
    signal result_array  : OUTPUT_ARRAY_VECTOR_16(0 to NUM_FILTERS-1, 
                                         0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                         0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1);
    signal result : WORD_ARRAY_16(0 to NUM_FILTERS-1) := (others => (others => '0')); 

    --- FSM signals
    type state_type is (IDLE, LOAD, COMPUTE, FINISH);
    signal current_state : state_type := IDLE;

    --- Current position in the input image
    signal row, col, c : integer := 0;

    --- What part of the input region we are in
    signal region_row, region_col : integer := 0;
    signal region_done : std_logic := '0';
    signal clear : std_logic := '0';

begin
    -- Generate MAC instances
    mac_gen : for i in 0 to NUM_FILTERS-1 generate
        mac_inst : entity work.MAC
            generic map (
                width_a => 8,
                width_b => 8,
                width_p => 16
            )
            port map (
                clk      => clk,
                rst      => rst,
                pixel_in => input_pixel,
                weights  => weights(i),
                valid    => valid,
                clear    => clear,
                result   => result(i),
                done     => done(i)
            );
    end generate;

    FSM_process: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            valid <= '0';
            clear <= '0';
            row <= 0;
            col <= 0;
            c <= 0;
            region_row <= 0;
            region_col <= 0;
            region_done <= '0';
            layer_done <= '0';
        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    clear <= '0';
                    layer_done <= '0';
                    if enable = '1' then
                        input_ready <= '1';
                        current_state <= LOAD;
                    end if;
                when LOAD =>
                    clear <= '0';
                    for filter in 0 to NUM_FILTERS-1 loop
                        
                        weights(filter) <= weight_array(filter, region_row, region_col);
                    end loop;

                    input_row <= row + region_row;
                    input_col <= col + region_col;

                    if input_valid = '1' then
                        valid <= '1';
                        input_ready <= '0';
                        current_state <= COMPUTE;
                    end if;
                when COMPUTE =>
                    if done = (done'range => '1') then 
                        valid <= '0';
                        current_state <= FINISH;
                    end if;
                when FINISH =>
                    if region_done = '1' then
                        -- Clear MAC accumulators and reset region tracking
                        clear <= '1';
                        region_done <= '0';
                        region_row <= 0;
                        region_col <= 0;
                        -- Store results before moving to next position
                        for filter in 0 to NUM_FILTERS-1 loop
                            result_array(filter, row, col) <= result(filter);
                        end loop;
                        
                        if col < (IMAGE_SIZE - KERNEL_SIZE)/STRIDE then
                            col <= col + 1;
                        elsif row < (IMAGE_SIZE - KERNEL_SIZE)/STRIDE then
                            row <= row + 1;
                            col <= 0;
                        else
                            -- All convolution complete
                            output_data <= result_array;
                            layer_done <= '1';
                            row <= 0;
                            col <= 0;
                        end if;
                        current_state <= IDLE;
                    else 
                        clear <= '0';
                        if region_col < KERNEL_SIZE - 1 then
                            region_col <= region_col + 1;
                            current_state <= LOAD;
                        elsif region_row < KERNEL_SIZE - 1 then
                            region_row <= region_row + 1;
                            region_col <= 0;
                            current_state <= LOAD;
                        else
                            region_done <= '1';
                            current_state <= FINISH;
                        end if;
                    end if;
                when others =>
                    current_state <= IDLE;
            end case;
        end if;
    end process;
    
end Behavioral;

