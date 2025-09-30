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
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;



entity conv_layer is
    generic (
        IMAGE_SIZE : integer := 28;
        KERNEL_SIZE : integer := 3;
        INPUT_CHANNELS : integer := 1;
        NUM_FILTERS : integer := 8;
        STRIDE : integer := 1;
        BLOCK_SIZE : integer := 2  -- Size of processing blocks (2x2, 3x3, etc.)
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
        output_pixel : out WORD_ARRAY_16(0 to NUM_FILTERS-1); -- 16-bit output pixel
        output_row : out integer; -- Current row of the output pixel
        output_col : out integer; -- Current column of the output pixel
        output_ready : in std_logic; -- High when ready for the next output

        layer_done : out STD_LOGIC
    );
end conv_layer;

architecture Behavioral of conv_layer is
    -- Weight and bias arrays loaded from COE files
    -- Data from layer_0_conv2d_weights.coe (Q1.6 format, 72 values for 8 filters, 3x3 each)
    -- The COE data is arranged linearly: [filter0_all_weights, filter1_all_weights, ...]
    -- We need to reshape it to [filter][row][col] format
    signal weight_array : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1,
                                            0 to KERNEL_SIZE-1,
                                            0 to KERNEL_SIZE-1) := (
        -- Filter 0: FE 11 03 | 14 EE 0F | 10 EB 01
        0 => (
            0 => (x"FE", x"11", x"03"),
            1 => (x"14", x"EE", x"0F"),
            2 => (x"10", x"EB", x"01")
        ),
        -- Filter 1: 08 10 02 | E6 07 11 | F7 00 0C
        1 => (
            0 => (x"08", x"10", x"02"),
            1 => (x"E6", x"07", x"11"),
            2 => (x"F7", x"00", x"0C")
        ),
        -- Filter 2: 08 05 FB | 00 F6 E7 | F9 10 17
        2 => (
            0 => (x"08", x"05", x"FB"),
            1 => (x"00", x"F6", x"E7"),
            2 => (x"F9", x"10", x"17")
        ),
        -- Filter 3: F9 FD 06 | FD FB EE | 18 0C 0F
        3 => (
            0 => (x"F9", x"FD", x"06"),
            1 => (x"FD", x"FB", x"EE"),
            2 => (x"18", x"0C", x"0F")
        ),
        -- Filter 4: 0C 14 17 | F5 FB F8 | 01 F8 06
        4 => (
            0 => (x"0C", x"14", x"17"),
            1 => (x"F5", x"FB", x"F8"),
            2 => (x"01", x"F8", x"06")
        ),
        -- Filter 5: FD 10 05 | 01 0E 01 | F3 13 05
        5 => (
            0 => (x"FD", x"10", x"05"),
            1 => (x"01", x"0E", x"01"),
            2 => (x"F3", x"13", x"05")
        ),
        -- Filter 6: 16 16 06 | 03 09 F0 | 16 1A F6
        6 => (
            0 => (x"16", x"16", x"06"),
            1 => (x"03", x"09", x"F0"),
            2 => (x"16", x"1A", x"F6")
        ),
        -- Filter 7: 0C 16 FF | 03 02 05 | 0E 13 11
        7 => (
            0 => (x"0C", x"16", x"FF"),
            1 => (x"03", x"02", x"05"),
            2 => (x"0E", x"13", x"11")
        )
    );
    
    -- Bias array from layer_0_conv2d_biases.coe: 00 00 00 00 00 00 00 04
    signal bias_array : WORD_ARRAY(0 to NUM_FILTERS-1) := (
        0 => x"00",  -- 0
        1 => x"00",  -- 0 
        2 => x"00",  -- 0
        3 => x"00",  -- 0
        4 => x"00",  -- 0
        5 => x"00",  -- 0
        6 => x"00",  -- 0
        7 => x"04"   -- 4
    );
    signal weights : WORD_ARRAY(0 to NUM_FILTERS-1) := (others => (others => '0'));    
    signal valid  : std_logic := '0';
    signal done : STD_LOGIC_VECTOR(NUM_FILTERS-1 downto 0) := (others => '0'); 
    signal result : WORD_ARRAY_16(0 to NUM_FILTERS-1) := (others => (others => '0')); -- MAC results

    --- FSM signals
    type state_type is (IDLE, LOAD, COMPUTE, FINISH);
    signal current_state : state_type := IDLE;
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
        --- Current position variables 
        variable position_counter : integer := 0;
        variable row, col : integer := 0;
        variable block_row, block_col : integer := 0;
        variable within_row, within_col : integer := 0;
        variable block_index : integer := 0;
        variable region_row, region_col : integer := 0;
    begin
        if rst = '1' then
            current_state <= IDLE;
            valid <= '0';
            clear <= '0';
            position_counter := 1;
            row := 0;
            col := 0;
            block_row := 0;
            block_col := 0;
            within_row := 0;
            within_col := 0;
            block_index := 0;
            region_row := 0;
            region_col := 0;
            region_done <= '0';
            layer_done <= '0';
        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    clear <= '0';
                    layer_done <= '0';
                    output_valid <= '0';
                    if enable = '1' then
                        current_state <= LOAD;
                    end if;
                when LOAD =>
                    clear <= '0';
                    for filter in 0 to NUM_FILTERS-1 loop
                    --- TEMP Should be loaded from memory or registers 
                        weights(filter) <= weight_array(filter, region_row, region_col);
                    end loop;

                    input_row <= row + region_row;
                    input_col <= col + region_col;
                    input_ready <= '1';

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
                        if output_ready = '1' then
                            -- Clear MAC accumulators and reset region tracking
                            region_done <= '0';
                            region_row := 0;
                            region_col := 0;
                            clear <= '1';
                            
                            -- Store results from frame before moving to next position (ReLU activation)
                            for filter in 0 to NUM_FILTERS-1 loop
                                if result(filter)(15) = '0' then  -- Check if MSB is 0 (positive number)
                                    output_pixel(filter) <= result(filter);
                                else 
                                    output_pixel(filter) <= (others => '0');  -- Output zero for negative numbers
                                end if;
                            end loop;
                            output_row <= row;
                            output_col <= col;
                            output_valid <= '1';
                            
                            -- FIXME check if this is correct
                            -- Generic block pattern calculation
                            -- Works for any BLOCK_SIZE (2x2, 3x3, 4x4, etc.)
                            position_counter := position_counter + 1;
                            
                            -- Calculate block coordinates and within-block position
                            block_index := (position_counter - 1) / (BLOCK_SIZE * BLOCK_SIZE);
                            within_row := ((position_counter - 1) mod (BLOCK_SIZE * BLOCK_SIZE)) / BLOCK_SIZE;
                            within_col := (position_counter - 1) mod BLOCK_SIZE;
                            
                            block_row := block_index / (IMAGE_SIZE / BLOCK_SIZE);
                            block_col := block_index mod (IMAGE_SIZE / BLOCK_SIZE);
                            
                            row := block_row * BLOCK_SIZE + within_row;
                            col := block_col * BLOCK_SIZE + within_col;
                            
                            -- Check if we've processed all positions
                            if position_counter >= (IMAGE_SIZE * IMAGE_SIZE) then
                                layer_done <= '1';
                                position_counter := 0;
                                row := 0;
                                col := 0;
                            end if;
                            current_state <= IDLE;
                        else 
                            output_valid <= '0'; -- Wait until output is ready
                            current_state <= FINISH;
                        end if;
                    else 
                        clear <= '0';
                        if region_col < KERNEL_SIZE - 1 then
                            region_col := region_col + 1;
                            current_state <= LOAD;
                        elsif region_row < KERNEL_SIZE - 1 then
                            region_row := region_row + 1;
                            region_col := 0;
                            current_state <= LOAD;
                        else
                            -- Region done
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

