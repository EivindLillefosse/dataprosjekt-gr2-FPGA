----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Modular Convolution Layer
-- Module Name: conv_layer_modular - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular convolution layer using separate components
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity conv_layer_modular is
    generic (
        IMAGE_SIZE     : integer := 28;
        KERNEL_SIZE    : integer := 3;
        INPUT_CHANNELS : integer := 1;
        NUM_FILTERS    : integer := 8;
        STRIDE         : integer := 1;
        BLOCK_SIZE     : integer := 2
    );
    Port ( 
        clk            : in STD_LOGIC;
        rst            : in STD_LOGIC;
        enable         : in STD_LOGIC;

        input_valid    : in std_logic;
        input_pixel    : in WORD;
        input_row      : inout integer;
        input_col      : inout integer;
        input_ready    : out std_logic;

        output_valid   : out std_logic;
        output_pixel   : out WORD_ARRAY_16(0 to NUM_FILTERS-1);
        output_row     : out integer;
        output_col     : out integer;
        output_ready   : in std_logic;

        layer_done     : out STD_LOGIC
    );
end conv_layer_modular;

architecture Behavioral of conv_layer_modular is

    -- Internal connection signals
    
    -- Weight memory controller signals
    signal weight_load_req   : std_logic;
    signal weight_kernel_row : integer range 0 to KERNEL_SIZE-1;
    signal weight_kernel_col : integer range 0 to KERNEL_SIZE-1;
    signal weight_data_valid : std_logic;
    signal weight_data       : WORD_ARRAY(0 to NUM_FILTERS-1);
    signal weight_load_done  : std_logic;
    
    -- Position calculator signals
    signal pos_advance    : std_logic;
    signal current_row    : integer;
    signal current_col    : integer;
    signal region_row     : integer range 0 to KERNEL_SIZE-1;
    signal region_col     : integer range 0 to KERNEL_SIZE-1;
    signal region_done    : std_logic;
    signal pos_layer_done : std_logic;
    
    -- Convolution engine signals
    signal compute_en : std_logic;
    signal compute_clear : std_logic;
    signal compute_done : std_logic_vector(NUM_FILTERS-1 downto 0);
    signal conv_results : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    
    -- ReLU activation signals
    signal relu_valid_in : std_logic;
    signal relu_data_out : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    signal relu_valid_out : std_logic;

begin

    -- Weight Memory Controller
    weight_mem_ctrl : entity work.weight_memory_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            KERNEL_SIZE => KERNEL_SIZE,
            ADDR_WIDTH => 7
        )
        port map (
            clk => clk,
            rst => rst,
            load_req => weight_load_req,
            kernel_row => weight_kernel_row,
            kernel_col => weight_kernel_col,
            weight_data => weight_data,
            data_valid => weight_data_valid,
            load_done => weight_load_done
        );

    -- Position Calculator
    pos_calc : entity work.position_calculator
        generic map (
            IMAGE_SIZE => IMAGE_SIZE,
            KERNEL_SIZE => KERNEL_SIZE,
            BLOCK_SIZE => BLOCK_SIZE
        )
        port map (
            clk => clk,
            rst => rst,
            advance => pos_advance,
            row => current_row,
            col => current_col,
            region_row => region_row,
            region_col => region_col,
            region_done => region_done,
            layer_done => pos_layer_done
        );

    -- Convolution Engine
    conv_engine : entity work.convolution_engine
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            MAC_DATA_WIDTH => 8,
            MAC_RESULT_WIDTH => 16
        )
        port map (
            clk => clk,
            rst => rst,
            clear => compute_clear,
            pixel_data => input_pixel,
            weight_data => weight_data,
            compute_en => compute_en,
            results => conv_results,
            compute_done => compute_done
        );

    -- ReLU Activation Layer
    relu : entity work.relu_layer
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            DATA_WIDTH => 16
        )
        port map (
            clk => clk,
            rst => rst,
            data_in => conv_results,
            data_valid => relu_valid_in,
            data_out => relu_data_out,
            valid_out => relu_valid_out
        );

    -- Main Controller FSM
    controller : entity work.convolution_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            KERNEL_SIZE => KERNEL_SIZE
        )
        port map (
            clk => clk,
            rst => rst,
            enable => enable,
            weight_load_req => weight_load_req,
            weight_kernel_row => weight_kernel_row,
            weight_kernel_col => weight_kernel_col,
            weight_data_valid => weight_data_valid,
            weight_load_done => weight_load_done,
            pos_advance => pos_advance,
            region_row => region_row,
            region_col => region_col,
            region_done => region_done,
            layer_done => pos_layer_done,
            compute_en => compute_en,
            compute_clear => compute_clear,
            compute_done => compute_done,
            input_ready => input_ready,
            input_valid => input_valid,
            output_valid => relu_valid_in,
            output_ready => output_ready
        );

    -- Connect position information
    input_row <= current_row + region_row;
    input_col <= current_col + region_col;
    
    -- Connect outputs
    output_pixel <= relu_data_out;
    output_row <= current_row;
    output_col <= current_col;
    output_valid <= relu_valid_out;
    layer_done <= pos_layer_done;

end Behavioral;