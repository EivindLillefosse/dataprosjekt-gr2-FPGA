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

    COMPONENT conv0_mem_weights
    PORT (
        clka : IN STD_LOGIC;
        ena : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
        douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) 
    );
    END COMPONENT;

    COMPONENT conv0_mem_bias
    PORT (
        clka : IN STD_LOGIC;
        ena : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) 
    );
    END COMPONENT;

    -- Memory interface signals
    signal weight_addr : std_logic_vector(6 downto 0) := (others => '0');
    signal weight_data : std_logic_vector(7 downto 0);
    signal weight_en   : std_logic := '0';
    
    signal bias_addr : std_logic_vector(2 downto 0) := (others => '0');
    signal bias_data : std_logic_vector(7 downto 0);
    signal bias_en   : std_logic := '0';

    signal weights : WORD_ARRAY(0 to NUM_FILTERS-1) := (others => (others => '0'));    
    signal valid  : std_logic := '0';
    signal done : STD_LOGIC_VECTOR(NUM_FILTERS-1 downto 0) := (others => '0'); 
    signal result : WORD_ARRAY_16(0 to NUM_FILTERS-1) := (others => (others => '0')); -- MAC results

    --- FSM signals
    type state_type is (IDLE, LOAD_WEIGHTS, WAIT_WEIGHTS, LOAD_DATA, COMPUTE, FINISH);
    signal current_state : state_type := IDLE;
    signal region_done : std_logic := '0';
    signal clear : std_logic := '0';

    -- Control signals for memory access
    signal current_filter : integer range 0 to NUM_FILTERS-1 := 0;


begin
    -- Instantiate weight memory
    weight_mem_inst : conv0_mem_weights
    PORT MAP (
        clka => clk,
        ena => weight_en,
        addra => weight_addr,
        douta => weight_data
    );

    bias_mem_inst : conv0_mem_bias
    PORT MAP (
        clka => clk,
        ena => bias_en,
        addra => bias_addr,
        douta => bias_data
    );

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
        -- BRAM read latency counter
        variable wait_cycles : integer := 0;
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
            wait_cycles := 0;
            region_done <= '0';
            layer_done <= '0';
            weight_addr <= (others => '0');
            bias_addr <= (others => '0');

        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    clear <= '0';
                    layer_done <= '0';
                    output_valid <= '0';
                    if enable = '1' then
                        current_filter <= 0;
                        current_state <= LOAD_WEIGHTS;
                    end if;

                when LOAD_WEIGHTS =>
                    -- Calculate address for current weight
                    weight_addr <= std_logic_vector(to_unsigned(
                        current_filter * (KERNEL_SIZE * KERNEL_SIZE) + 
                        (region_row * KERNEL_SIZE + region_col), 7));
                    weight_en <= '1';
                    wait_cycles := 0;  -- Reset wait counter
                    current_state <= WAIT_WEIGHTS;

                when WAIT_WEIGHTS =>
                    -- Simple counter-based wait for BRAM read latency
                    wait_cycles := wait_cycles + 1;
                    if wait_cycles >= 2 then  -- Wait 2 cycles for registered BRAM output
                        weight_en <= '0';
                        current_state <= LOAD_DATA;
                    end if;

                when LOAD_DATA =>
                    weight_en <= '0';
                    -- Load weight data for current filter
                    weights(current_filter) <= weight_data;
                    
                    if current_filter < NUM_FILTERS - 1 then
                        current_filter <= current_filter + 1;
                        current_state <= LOAD_WEIGHTS;
                    else
                        -- All weights loaded for this position
                        
                        input_row <= row + region_row;
                        input_col <= col + region_col;
                        input_ready <= '1';

                        if input_valid = '1' then
                            current_filter <= 0;
                            valid <= '1';
                            input_ready <= '0';
                            current_state <= COMPUTE;
                        end if;
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
                            current_state <= LOAD_WEIGHTS;  -- Go back to load new weights
                        elsif region_row < KERNEL_SIZE - 1 then
                            region_row := region_row + 1;
                            region_col := 0;
                            current_state <= LOAD_WEIGHTS;  -- Go back to load new weights
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

