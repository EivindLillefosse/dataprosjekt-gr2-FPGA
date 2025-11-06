----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse, Martin Brekke Nilsen, Nikolai Sandvik Nore
-- 
-- Create Date: 31.10.2025
-- Design Name: CNN Accelerator (Debug Version)
-- Module Name: cnn_top_debug
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Top-level module for CNN Accelerator with debug ports
--
----------------------------------------------------------------------------------

library IEEE;   
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity cnn_top_debug is
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

        -- Request FROM external controller (what output position is needed)
        output_req_row   : in  integer;
        output_req_col   : in  integer;
        output_req_valid : in  std_logic;
        output_req_ready : out std_logic;

        -- Request TO input provider (what input positions we need)
        input_req_row    : out integer;
        input_req_col    : out integer;
        input_req_valid  : out std_logic;
        input_req_ready  : in  std_logic;

        -- Data FROM input provider
        input_pixel      : in  WORD_ARRAY(0 to CONV_1_INPUT_CHANNELS-1);
        input_valid      : in  std_logic;
        input_ready      : out std_logic;

        -- Data TO external consumer (final output)
        output_pixel     : out WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
        output_valid     : out std_logic;
        output_ready     : in  std_logic;

        -- DEBUG: Intermediate layer outputs
        -- Conv1 output (after convolution, before pool1)
        debug_conv1_pixel       : out WORD_ARRAY(0 to CONV_1_NUM_FILTERS-1);
        debug_conv1_valid       : out std_logic;
        debug_conv1_ready       : in  std_logic;
        debug_conv1_row         : out integer;
        debug_conv1_col         : out integer;
        
        -- Pool1 output (after first pooling, before conv2)
        debug_pool1_pixel       : out WORD_ARRAY(0 to CONV_1_NUM_FILTERS-1);
        debug_pool1_valid       : out std_logic;
        debug_pool1_ready       : in  std_logic;
        debug_pool1_row         : out integer;
        debug_pool1_col         : out integer;
        
        -- Conv2 output (after second convolution, before pool2)
        debug_conv2_pixel       : out WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
        debug_conv2_valid       : out std_logic;
        debug_conv2_ready       : in  std_logic;
        debug_conv2_row         : out integer;
        debug_conv2_col         : out integer
    );
end cnn_top_debug;

architecture Structural of cnn_top_debug is

    -- Signals between conv1 and pool1 (request/response protocol)
    signal conv1_out_req_row    : integer;
    signal conv1_out_req_col    : integer;
    signal conv1_out_req_valid  : std_logic;
    signal conv1_out_req_ready  : std_logic;
    
    signal conv1_in_req_row     : integer;
    signal conv1_in_req_col     : integer;
    signal conv1_in_req_valid   : std_logic;
    signal conv1_in_req_ready   : std_logic;
    
    signal conv1_pixel_out      : WORD_ARRAY(0 to CONV_1_NUM_FILTERS-1);
    signal conv1_pixel_out_valid: std_logic;
    signal conv1_pixel_out_ready: std_logic;
    
    signal conv1_pixel_in       : WORD_ARRAY(0 to CONV_1_INPUT_CHANNELS-1);
    signal conv1_pixel_in_valid : std_logic;
    signal conv1_pixel_in_ready : std_logic;

    -- Signals between pool1 and conv2 (request/response protocol)
    signal pool1_out_req_row    : integer;
    signal pool1_out_req_col    : integer;
    signal pool1_out_req_valid  : std_logic;
    signal pool1_out_req_ready  : std_logic;
    
    signal pool1_in_req_row     : integer;
    signal pool1_in_req_col     : integer;
    signal pool1_in_req_valid   : std_logic;
    signal pool1_in_req_ready   : std_logic;
    
    signal pool1_pixel_out      : WORD_ARRAY(0 to CONV_1_NUM_FILTERS-1);
    signal pool1_pixel_out_valid: std_logic;
    signal pool1_pixel_out_ready: std_logic;

    -- Signals between conv2 and pool2 (request/response protocol)
    signal conv2_out_req_row    : integer;
    signal conv2_out_req_col    : integer;
    signal conv2_out_req_valid  : std_logic;
    signal conv2_out_req_ready  : std_logic;
    
    signal conv2_in_req_row     : integer;
    signal conv2_in_req_col     : integer;
    signal conv2_in_req_valid   : std_logic;
    signal conv2_in_req_ready   : std_logic;
    
    signal conv2_pixel_out      : WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
    signal conv2_pixel_out_valid: std_logic;
    signal conv2_pixel_out_ready: std_logic;

    -- Signals between pool2 and output (request/response protocol)
    signal pool2_in_req_row     : integer;
    signal pool2_in_req_col     : integer;
    signal pool2_in_req_valid   : std_logic;
    signal pool2_in_req_ready   : std_logic;

    -- DEBUG: Register output positions when request handshake completes
    signal conv1_active_out_row : integer := 0;
    signal conv1_active_out_col : integer := 0;
    signal pool1_active_out_row : integer := 0;
    signal pool1_active_out_col : integer := 0;
    signal conv2_active_out_row : integer := 0;
    signal conv2_active_out_col : integer := 0;

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
            clk                 => clk,
            rst                 => rst,
            enable              => enable,

            -- Request FROM pool1 (what output position pool1 needs)
            pixel_out_req_row   => conv1_out_req_row,
            pixel_out_req_col   => conv1_out_req_col,
            pixel_out_req_valid => conv1_out_req_valid,
            pixel_out_req_ready => conv1_out_req_ready,

            -- Request TO input provider
            pixel_in_req_row    => conv1_in_req_row,
            pixel_in_req_col    => conv1_in_req_col,
            pixel_in_req_valid  => conv1_in_req_valid,
            pixel_in_req_ready  => conv1_in_req_ready,

            -- Data FROM input provider
            pixel_in            => conv1_pixel_in,
            pixel_in_valid      => conv1_pixel_in_valid,
            pixel_in_ready      => conv1_pixel_in_ready,

            -- Data TO pool1
            pixel_out           => conv1_pixel_out,
            pixel_out_valid     => conv1_pixel_out_valid,
            pixel_out_ready     => conv1_pixel_out_ready
        );
        
    -- Instantiate 1st Pooling layer
    pooling_layer1: entity work.max_pooling
        generic map (
            INPUT_SIZE     => ((IMAGE_SIZE - CONV_1_KERNEL_SIZE + 1) / CONV_1_STRIDE),
            INPUT_CHANNELS => CONV_1_NUM_FILTERS,
            BLOCK_SIZE     => POOL_1_BLOCK_SIZE
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            
            -- Request FROM conv2 (what output position conv2 needs)
            pixel_out_req_row   => pool1_out_req_row,
            pixel_out_req_col   => pool1_out_req_col,
            pixel_out_req_valid => pool1_out_req_valid,
            pixel_out_req_ready => pool1_out_req_ready,

            -- Request TO conv1
            pixel_in_req_row    => pool1_in_req_row,
            pixel_in_req_col    => pool1_in_req_col,
            pixel_in_req_valid  => pool1_in_req_valid,
            pixel_in_req_ready  => pool1_in_req_ready,

            -- Data FROM conv1
            pixel_in            => conv1_pixel_out,
            pixel_in_valid      => conv1_pixel_out_valid,
            pixel_in_ready      => conv1_pixel_out_ready,

            -- Data TO conv2
            pixel_out           => pool1_pixel_out,
            pixel_out_valid     => pool1_pixel_out_valid,
            pixel_out_ready     => pool1_pixel_out_ready
        );

    -- Connect pool1 output requests to conv1 input requests
    conv1_out_req_row   <= pool1_in_req_row;
    conv1_out_req_col   <= pool1_in_req_col;
    conv1_out_req_valid <= pool1_in_req_valid;
    pool1_in_req_ready  <= conv1_out_req_ready;

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
            clk                 => clk,
            rst                 => rst,
            enable              => enable,
            
            -- Request FROM pool2 (what output position pool2 needs)
            pixel_out_req_row   => conv2_out_req_row,
            pixel_out_req_col   => conv2_out_req_col,
            pixel_out_req_valid => conv2_out_req_valid,
            pixel_out_req_ready => conv2_out_req_ready,

            -- Request TO pool1
            pixel_in_req_row    => conv2_in_req_row,
            pixel_in_req_col    => conv2_in_req_col,
            pixel_in_req_valid  => conv2_in_req_valid,
            pixel_in_req_ready  => conv2_in_req_ready,

            -- Data FROM pool1
            pixel_in            => pool1_pixel_out,
            pixel_in_valid      => pool1_pixel_out_valid,
            pixel_in_ready      => pool1_pixel_out_ready,

            -- Data TO pool2
            pixel_out           => conv2_pixel_out,
            pixel_out_valid     => conv2_pixel_out_valid,
            pixel_out_ready     => conv2_pixel_out_ready
        );

    -- Connect conv2 output requests to pool1 input requests
    pool1_out_req_row   <= conv2_in_req_row;
    pool1_out_req_col   <= conv2_in_req_col;
    pool1_out_req_valid <= conv2_in_req_valid;
    conv2_in_req_ready  <= pool1_out_req_ready;

    -- Instantiate 2nd Pooling layer (final output)
    pooling_layer2: entity work.max_pooling
        generic map (
            INPUT_SIZE     => ((CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1) / CONV_2_STRIDE),
            INPUT_CHANNELS => CONV_2_NUM_FILTERS,
            BLOCK_SIZE     => POOL_2_BLOCK_SIZE
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            
            -- Request FROM external controller
            pixel_out_req_row   => output_req_row,
            pixel_out_req_col   => output_req_col,
            pixel_out_req_valid => output_req_valid,
            pixel_out_req_ready => output_req_ready,

            -- Request TO conv2
            pixel_in_req_row    => pool2_in_req_row,
            pixel_in_req_col    => pool2_in_req_col,
            pixel_in_req_valid  => pool2_in_req_valid,
            pixel_in_req_ready  => pool2_in_req_ready,

            -- Data FROM conv2
            pixel_in            => conv2_pixel_out,
            pixel_in_valid      => conv2_pixel_out_valid,
            pixel_in_ready      => conv2_pixel_out_ready,

            -- Data TO external consumer
            pixel_out           => output_pixel,
            pixel_out_valid     => output_valid,
            pixel_out_ready     => output_ready
        );

    -- Connect pool2 output requests to conv2 input requests
    conv2_out_req_row   <= pool2_in_req_row;
    conv2_out_req_col   <= pool2_in_req_col;
    conv2_out_req_valid <= pool2_in_req_valid;
    pool2_in_req_ready  <= conv2_out_req_ready;

    -- Connect top-level input requests to conv1's input requests
    input_req_row    <= conv1_in_req_row;
    input_req_col    <= conv1_in_req_col;
    input_req_valid  <= conv1_in_req_valid;
    conv1_in_req_ready <= input_req_ready;

    -- Connect top-level input data to conv1's input data
    conv1_pixel_in       <= input_pixel;
    conv1_pixel_in_valid <= input_valid;
    input_ready          <= conv1_pixel_in_ready;

    -- DEBUG: Tap intermediate layer outputs
    -- Register the active output position when request handshake completes
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                conv1_active_out_row <= 0;
                conv1_active_out_col <= 0;
                pool1_active_out_row <= 0;
                pool1_active_out_col <= 0;
                conv2_active_out_row <= 0;
                conv2_active_out_col <= 0;
            else
                -- Capture Conv1's output position when request is accepted
                if conv1_out_req_valid = '1' and conv1_out_req_ready = '1' then
                    conv1_active_out_row <= conv1_out_req_row;
                    conv1_active_out_col <= conv1_out_req_col;
                end if;
                
                -- Capture Pool1's output position when request is accepted
                if pool1_out_req_valid = '1' and pool1_out_req_ready = '1' then
                    pool1_active_out_row <= pool1_out_req_row;
                    pool1_active_out_col <= pool1_out_req_col;
                end if;
                
                -- Capture Conv2's output position when request is accepted
                if conv2_out_req_valid = '1' and conv2_out_req_ready = '1' then
                    conv2_active_out_row <= conv2_out_req_row;
                    conv2_active_out_col <= conv2_out_req_col;
                end if;
            end if;
        end if;
    end process;

    -- Conv1 output tap (before pool1 consumption)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                debug_conv1_pixel <= (others => (others => '0'));
                debug_conv1_valid <= '0';
                debug_conv1_row <= 0;
                debug_conv1_col <= 0;
            else
                -- Capture conv1 output when valid, along with the active output position
                if conv1_pixel_out_valid = '1' then
                    debug_conv1_pixel <= conv1_pixel_out;
                    debug_conv1_valid <= '1';
                    -- Use the registered active position
                    debug_conv1_row <= conv1_active_out_row;
                    debug_conv1_col <= conv1_active_out_col;
                elsif debug_conv1_ready = '1' then
                    debug_conv1_valid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Pool1 output tap (before conv2 consumption)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                debug_pool1_pixel <= (others => (others => '0'));
                debug_pool1_valid <= '0';
                debug_pool1_row <= 0;
                debug_pool1_col <= 0;
            else
                -- Capture pool1 output when valid, along with the active output position
                if pool1_pixel_out_valid = '1' then
                    debug_pool1_pixel <= pool1_pixel_out;
                    debug_pool1_valid <= '1';
                    -- Use the registered active position
                    debug_pool1_row <= pool1_active_out_row;
                    debug_pool1_col <= pool1_active_out_col;
                elsif debug_pool1_ready = '1' then
                    debug_pool1_valid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Conv2 output tap (before pool2 consumption)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                debug_conv2_pixel <= (others => (others => '0'));
                debug_conv2_valid <= '0';
                debug_conv2_row <= 0;
                debug_conv2_col <= 0;
            else
                -- Capture conv2 output when valid, along with the active output position
                if conv2_pixel_out_valid = '1' then
                    debug_conv2_pixel <= conv2_pixel_out;
                    debug_conv2_valid <= '1';
                    -- Use the registered active position
                    debug_conv2_row <= conv2_active_out_row;
                    debug_conv2_col <= conv2_active_out_col;
                elsif debug_conv2_ready = '1' then
                    debug_conv2_valid <= '0';
                end if;
            end if;
        end if;
    end process;

end Structural;
