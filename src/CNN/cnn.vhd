----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse, Martin Brekke Nilsen, Nikolai Sandvik Nore
-- 
-- Create Date: 31.10.2025
-- Design Name: CNN Accelerator
-- Module Name: cnn_top
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Top-level module for CNN Accelerator (Clean version without debug ports)
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
        POOL_2_BLOCK_SIZE     : integer := 2;
        
        -- Parameters for fully connected layers
        FC1_NODES_IN      : integer := (((CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1) / CONV_2_STRIDE) / POOL_2_BLOCK_SIZE) * 
                                        (((CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1) / CONV_2_STRIDE) / POOL_2_BLOCK_SIZE) * 
                                        CONV_2_NUM_FILTERS;  -- 5*5*16 = 400
        FC1_NODES_OUT     : integer := 64;
        FC2_NODES_OUT     : integer := 10  -- Final classification output
    
    );
    port (
        -- Control signals
        clk          : in  std_logic;
        rst          : in  std_logic;
        enable       : in  std_logic;

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
        output_guess     : out WORD;  -- Final classification (after argmax) - placeholder for now
        output_valid     : out std_logic;
        output_ready     : in  std_logic;
        
        -- FC1 outputs (intermediate, for testing/debug)
        fc1_output_data  : out WORD_ARRAY(0 to 63);  -- 64 outputs from FC1
        fc1_output_valid : out std_logic;
        fc1_output_ready : in  std_logic;
        
        -- FC2 outputs (final 10-class classification)
        fc2_output_data  : out WORD_ARRAY(0 to 9);   -- 10 class scores
        fc2_output_valid : out std_logic;
        fc2_output_ready : in  std_logic
    );
end cnn_top;

architecture Structural of cnn_top is

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

    -- Signals between pool2 and calc_index
    signal pool2_pixel_out       : WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
    signal pool2_pixel_out_valid : std_logic;
    signal pool2_pixel_out_ready : std_logic;
    
    signal pool2_in_req_row      : integer;
    signal pool2_in_req_col      : integer;
    signal pool2_in_req_valid    : std_logic;
    signal pool2_in_req_ready    : std_logic;

    -- Signals between calc_index and fc1
    signal calc_index_enable     : std_logic;
    signal calc_req_row          : integer;
    signal calc_req_col          : integer;
    signal calc_req_valid        : std_logic;
    signal calc_fc_pixel         : WORD;
    signal calc_fc_valid         : std_logic;
    signal calc_curr_index       : integer range 0 to FC1_NODES_IN-1;
    signal calc_done             : std_logic;

    -- Signals for FC1 output
    signal fc1_out_valid         : std_logic;
    signal fc1_out_ready         : std_logic;
    signal fc1_out_data          : WORD_ARRAY(0 to FC1_NODES_OUT-1);
    signal fc1_in_ready          : std_logic;

    -- Signals for buffer between FC1 and FC2
    signal buf_out_valid         : std_logic;
    signal buf_out_data          : WORD_ARRAY(0 to FC1_NODES_OUT-1);
    signal buf_out_ready         : std_logic;
    signal buf_in_ready          : std_logic;
    
    -- Signals for FC2 input sequencer
    signal fc2_input_index       : integer range 0 to FC1_NODES_OUT-1 := 0;
    signal fc2_input_valid       : std_logic;
    signal fc2_input_data        : WORD;
    signal fc2_sending           : std_logic;  -- State: actively sending to FC2
    
    -- Signals for FC2 output
    signal fc2_out_valid         : std_logic;
    signal fc2_out_data          : WORD_ARRAY(0 to FC2_NODES_OUT-1);
    signal fc2_in_ready          : std_logic;

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

    -- Connect pool2 output requests to conv2 input requests
    conv2_out_req_row   <= pool2_in_req_row;
    conv2_out_req_col   <= pool2_in_req_col;
    conv2_out_req_valid <= pool2_in_req_valid;
    pool2_in_req_ready  <= conv2_out_req_ready;

    -- Instantiate 2nd Pooling layer
    pooling_layer2: entity work.max_pooling
        generic map (
            INPUT_SIZE     => ((CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1) / CONV_2_STRIDE),
            INPUT_CHANNELS => CONV_2_NUM_FILTERS,
            BLOCK_SIZE     => POOL_2_BLOCK_SIZE
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            
            -- Request FROM calc_index (what output position calc_index needs)
            pixel_out_req_row   => calc_req_row,
            pixel_out_req_col   => calc_req_col,
            pixel_out_req_valid => calc_req_valid,
            pixel_out_req_ready => open,  -- calc_index doesn't need ready

            -- Request TO conv2
            pixel_in_req_row    => pool2_in_req_row,
            pixel_in_req_col    => pool2_in_req_col,
            pixel_in_req_valid  => pool2_in_req_valid,
            pixel_in_req_ready  => pool2_in_req_ready,

            -- Data FROM conv2
            pixel_in            => conv2_pixel_out,
            pixel_in_valid      => conv2_pixel_out_valid,
            pixel_in_ready      => conv2_pixel_out_ready,

            -- Data TO calc_index (all 16 channels)
            pixel_out           => pool2_pixel_out,
            pixel_out_valid     => pool2_pixel_out_valid,
            pixel_out_ready     => '1'  -- calc_index always ready
        );

    -- Instantiate calc_index (flattens 3D tensor to 1D for FC layer)
    calc_index_inst: entity work.calc_index
        generic map (
            NODES_IN       => FC1_NODES_IN,      -- 400
            INPUT_CHANNELS => CONV_2_NUM_FILTERS, -- 16
            INPUT_SIZE     => (((CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1) / CONV_2_STRIDE) / POOL_2_BLOCK_SIZE)  -- 5
        )
        port map (
            clk             => clk,
            rst             => rst,
            enable          => calc_index_enable,
            
            -- Request TO pool2
            req_row         => calc_req_row,
            req_col         => calc_req_col,
            req_valid       => calc_req_valid,
            
            -- Input FROM pool2 (all 16 channels at once)
            pool_pixel_data => pool2_pixel_out,
            
            -- Output TO fc1 (selected single channel pixel)
            fc_pixel_out    => calc_fc_pixel,
            fc_pixel_valid  => calc_fc_valid,
            
            curr_index      => calc_curr_index,
            done            => calc_done
        );

    -- Enable calc_index when CNN is enabled
    calc_index_enable <= enable;

    -- Instantiate FC1 layer (400 inputs -> 64 outputs)
    fc1_inst: entity work.fullyconnected
        generic map (
            NODES_IN  => FC1_NODES_IN,   -- 400
            NODES_OUT => FC1_NODES_OUT,  -- 64
            LAYER_ID  => 0               -- First FC layer (uses layer_5_dense weights/biases)
        )
        port map (
            clk             => clk,
            rst             => rst,
            
            -- Input FROM calc_index
            pixel_in_valid  => calc_fc_valid,
            pixel_in_ready  => fc1_in_ready,
            pixel_in_data   => calc_fc_pixel,
            pixel_in_index  => calc_curr_index,
            
            -- Output TO buffer
            pixel_out_valid => fc1_out_valid,
            pixel_out_ready => buf_in_ready,
            pixel_out_data  => fc1_out_data
        );

    -- Buffer between FC1 and FC2
    fc_buffer: entity work.fc_layer_buffer
        generic map (
            DATA_WIDTH  => 8,
            NUM_NEURONS => FC1_NODES_OUT  -- 64
        )
        port map (
            clk          => clk,
            rst          => rst,
            
            -- Input FROM FC1
            input_valid  => fc1_out_valid,
            input_data   => fc1_out_data,
            input_ready  => buf_in_ready,  -- Buffer tells FC1 it's ready
            
            -- Output TO FC2 sequencer
            output_valid => buf_out_valid,
            output_data  => buf_out_data,
            output_ready => buf_out_ready
        );

    -- FC2 input sequencer: send buffered 64 neurons sequentially
    fc2_input_data <= buf_out_data(fc2_input_index);
    
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fc2_input_index <= 0;
                fc2_input_valid <= '0';
                fc2_sending <= '0';
            elsif buf_out_valid = '1' and fc2_sending = '0' then
                -- Buffer has full output, start sending to FC2
                fc2_sending <= '1';
                fc2_input_valid <= '1';
                fc2_input_index <= 0;
            elsif fc2_sending = '1' and fc2_in_ready = '1' then
                -- FC2 accepted current pixel, advance
                if fc2_input_index = FC1_NODES_OUT - 1 then
                    -- Last pixel sent, done
                    fc2_input_index <= 0;
                    fc2_input_valid <= '0';
                    fc2_sending <= '0';
                else
                    -- Send next pixel
                    fc2_input_index <= fc2_input_index + 1;
                    fc2_input_valid <= '1';  -- Keep valid high
                end if;
            end if;
        end if;
    end process;
    
    -- Tell buffer we're ready to drain it during FC2 transmission
    -- Assert ready whenever we're sending data to FC2 (draining the buffer)
    buf_out_ready <= '1' when fc2_sending = '1' else '0';

    -- Instantiate FC2 layer (64 inputs -> 10 outputs)
    fc2_inst: entity work.fullyconnected
        generic map (
            NODES_IN  => FC1_NODES_OUT,  -- 64
            NODES_OUT => FC2_NODES_OUT,  -- 10
            LAYER_ID  => 1               -- Second FC layer (uses layer_6_dense_1 weights/biases)
        )
        port map (
            clk             => clk,
            rst             => rst,
            
            -- Input FROM buffer sequencer
            pixel_in_valid  => fc2_input_valid,
            pixel_in_ready  => fc2_in_ready,
            pixel_in_data   => fc2_input_data,
            pixel_in_index  => fc2_input_index,
            
            -- Output (FC2 doesn't use input ready signal)
            pixel_out_valid => fc2_out_valid,
            pixel_out_ready => open,  -- Not used, just an indicator
            pixel_out_data  => fc2_out_data
        );

    -- Connect FC1 output to top-level output (for debug)
    fc1_output_data  <= fc1_out_data;
    fc1_output_valid <= fc1_out_valid;
    fc1_out_ready    <= fc1_output_ready;  -- Connect ready from top-level port
    
    -- Connect FC2 output to top-level output
    fc2_output_data  <= fc2_out_data;
    fc2_output_valid <= fc2_out_valid;
    
    -- Placeholder for output_guess (will be driven by argmax)
    output_guess  <= (others => '0');
    output_valid  <= fc2_out_valid;  -- Use FC2 valid for final output

    -- Connect top-level input requests to conv1's input requests
    input_req_row    <= conv1_in_req_row;
    input_req_col    <= conv1_in_req_col;
    input_req_valid  <= conv1_in_req_valid;
    conv1_in_req_ready <= input_req_ready;

    -- Connect top-level input data to conv1's input data
    conv1_pixel_in       <= input_pixel;
    conv1_pixel_in_valid <= input_valid;
    input_ready          <= conv1_pixel_in_ready;

end Structural;
