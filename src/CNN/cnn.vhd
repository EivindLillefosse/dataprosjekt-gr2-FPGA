----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse, Martin Brekke Nilsen, Nikolai Sandvik Nore
-- 
-- Create Date: 31.10.2025
-- Design Name: CNN Accelerator
-- Module Name: cnn_top
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Top-level module for CNN Accelerator
--
----------------------------------------------------------------------------------

library IEEE;   
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity cnn_top is
    generic (
        IMAGE_SIZE     : integer := 28;
        -- Parameters for 1st convolution layer
        CONV_1_IMAGE_SIZE     : integer := IMAGE_SIZE;
        CONV_1_KERNEL_SIZE    : integer := 3;
        CONV_1_INPUT_CHANNELS : integer := 1;
        CONV_1_NUM_FILTERS    : integer := 8;
        CONV_1_STRIDE         : integer := 1;
        CONV_1_BLOCK_SIZE     : integer := 2;

        -- Parameters for 1st pooling layer
        POOL_1_BLOCK_SIZE     : integer := 2;

        -- Parameters for 2nd convolution layer
        CONV_2_IMAGE_SIZE     : integer := ((IMAGE_SIZE - CONV_1_KERNEL_SIZE + 1) / CONV_1_STRIDE)/ POOL_1_BLOCK_SIZE;
        CONV_2_KERNEL_SIZE    : integer := 3;
        CONV_2_INPUT_CHANNELS : integer := 8;
        CONV_2_NUM_FILTERS    : integer := 16;
        CONV_2_STRIDE         : integer := 1;
        CONV_2_BLOCK_SIZE     : integer := 2;

        -- Parameters for 2nd pooling layer
        POOL_2_BLOCK_SIZE     : integer := 2
    
    );
    port (
        -- Control signals
        clk          : in  std_logic;
        rst          : in  std_logic;
        enable       : in  std_logic;

    -- Input interface
    input_valid  : in  std_logic;
    input_pixel  : in  WORD_ARRAY(0 to CONV_1_INPUT_CHANNELS-1);
        input_row    : out integer;
        input_col    : out integer;
        input_ready  : out std_logic;

        -- Output interface
        output_valid : out std_logic;
        output_pixel : out WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
        output_row   : out integer;
        output_col   : out integer;
        output_ready : in  std_logic;

        layer_done   : out std_logic
    );
end cnn_top;

architecture Structural of cnn_top is

    -- Signals between conv1 and pool1
    signal conv1_output_valid : std_logic;
    signal conv1_output_pixel : WORD_ARRAY(0 to CONV_1_NUM_FILTERS-1);
    signal conv1_output_row   : integer;
    signal conv1_output_col   : integer;
    signal conv1_output_ready : std_logic := '0';
    signal conv1_layer_done   : std_logic;

    -- Signals between pool1 and conv2
    signal pooling_output_pixel : WORD_ARRAY(0 to CONV_1_NUM_FILTERS-1);
    signal pooling_output_ready : std_logic;
    signal pooling_output_valid : std_logic;
    signal pooling_output_row   : integer;
    signal pooling_output_col   : integer;

    -- Signals between conv2 and pool2 (final output)
    signal final_output_pixel : WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
    signal final_output_ready : std_logic;
    -- Intermediate signals for conv2 <-> pool2 chaining
    signal conv2_output_valid : std_logic;
    signal conv2_output_pixel : WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
    signal conv2_output_row   : integer;
    signal conv2_output_col   : integer;
    signal conv2_output_ready : std_logic;

begin
    -- Instantiate 1st convolution layer
    conv_layer1: entity work.conv_layer_modular
        generic map (
            IMAGE_SIZE     => CONV_1_IMAGE_SIZE,
            KERNEL_SIZE    => CONV_1_KERNEL_SIZE,
            INPUT_CHANNELS => CONV_1_INPUT_CHANNELS,
            NUM_FILTERS    => CONV_1_NUM_FILTERS,
            STRIDE         => CONV_1_STRIDE,
            BLOCK_SIZE     => CONV_1_BLOCK_SIZE,
            LAYER_ID       => 0
        )
        port map (
            clk            => clk,
            rst            => rst,
            enable         => enable,

            -- Input interface
            input_valid    => input_valid,
            input_pixel    => input_pixel,
            input_row      => input_row,
            input_col      => input_col,
            input_ready    => input_ready,

            -- Output interface
            output_valid   => conv1_output_valid,
            output_pixel   => conv1_output_pixel,
            output_row     => conv1_output_row,
            output_col     => conv1_output_col,
            output_ready   => conv1_output_ready,
            layer_done     => conv1_layer_done
        );
    -- Instantiate 1st Pooling layer
    pooling_layer1: entity work.max_pooling
        generic map (
            INPUT_SIZE  => ((IMAGE_SIZE - CONV_1_KERNEL_SIZE + 1) / CONV_1_STRIDE),
            BLOCK_SIZE  => POOL_1_BLOCK_SIZE
        )
        port map (
            clk             => clk,
            rst           => rst,
            pixel_in_valid  => conv1_output_valid,
            pixel_in_ready  => conv1_output_ready,
            pixel_in        => conv1_output_pixel,
            pixel_in_row    => conv1_output_row,
            pixel_in_col    => conv1_output_col,
            pixel_out       => pooling_output_pixel,
            pixel_out_ready => pooling_output_valid
        );

    -- Instantiate 2nd convolution layer (takes pooling output)
    conv_layer2: entity work.conv_layer_modular
        generic map (
            IMAGE_SIZE     => CONV_2_IMAGE_SIZE,
            KERNEL_SIZE    => CONV_2_KERNEL_SIZE,
            INPUT_CHANNELS => CONV_2_INPUT_CHANNELS,
            NUM_FILTERS    => CONV_2_NUM_FILTERS,
            STRIDE         => CONV_2_STRIDE,
            BLOCK_SIZE     => CONV_2_BLOCK_SIZE,
            LAYER_ID       => 1
        )
        port map (
            clk            => clk,
            rst            => rst,
            enable         => enable,
            input_valid    => pooling_output_valid,
            input_pixel    => pooling_output_pixel,
            input_row      => pooling_output_row,
            input_col      => pooling_output_col,
            input_ready    => open,
            output_valid   => conv2_output_valid,
            output_pixel   => conv2_output_pixel,
            output_row     => conv2_output_row,
            output_col     => conv2_output_col,
            output_ready   => conv2_output_ready,
            layer_done     => layer_done
        );

    -- Instantiate 2nd Pooling layer (final output)
    pooling_layer2: entity work.max_pooling
        generic map (
            INPUT_SIZE  => ((CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1) / CONV_2_STRIDE),
            INPUT_CHANNELS => CONV_2_NUM_FILTERS,
            BLOCK_SIZE  => POOL_2_BLOCK_SIZE
        )
        port map (
            clk             => clk,
            rst           => rst,
            pixel_in_valid  => conv2_output_valid,
            pixel_in_ready  => conv2_output_ready,
            pixel_in        => conv2_output_pixel,
            pixel_in_row    => conv2_output_row,
            pixel_in_col    => conv2_output_col,
            pixel_out       => final_output_pixel,
            pixel_out_ready => final_output_ready
        );

    -- Connect final outputs to top-level ports
    output_valid <= final_output_ready;
    output_pixel <= final_output_pixel;
    output_row <= conv2_output_row;
    output_col <= conv2_output_col;
    end Structural;
