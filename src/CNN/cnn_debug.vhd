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
        output_guess     : out WORD;  -- Final classification (placeholder)
        
        -- Control: Select between testbench requests and calc_index requests for Pool2
        use_fc_path      : in  std_logic;  -- '1' = calc_index controls Pool2, '0' = testbench controls Pool2
        
        -- FC1 outputs (for testing/debug)
        fc1_output_data  : out WORD_ARRAY(0 to 63);
        fc1_output_valid : out std_logic;
        fc1_output_ready : in  std_logic;
        
        -- FC2 outputs (final 10-class classification)
        fc2_output_data  : out WORD_ARRAY(0 to 9);
        fc2_output_valid : out std_logic;
        fc2_output_ready : in  std_logic;

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
        debug_conv2_col         : out integer;
        
        -- Pool2 output (after second pooling, before FC layers)
        debug_pool2_pixel       : out WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
        debug_pool2_valid       : out std_logic;
        debug_pool2_ready       : in  std_logic;
        debug_pool2_row         : out integer;
        debug_pool2_col         : out integer;
        
        -- DEBUG: calc_index status
        debug_calc_index        : out integer range 0 to 399;
        debug_calc_pixel        : out WORD;
        debug_calc_valid        : out std_logic;
        debug_calc_done         : out std_logic
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
    
    -- Pool2 output signals
    signal pool2_pixel_out       : WORD_ARRAY(0 to CONV_2_NUM_FILTERS-1);
    signal pool2_pixel_out_valid : std_logic;
    signal pool2_pixel_out_ready : std_logic;
    
    -- Signals between calc_index and fc1
    signal calc_index_enable     : std_logic;
    signal calc_req_row          : integer;
    signal calc_req_col          : integer;
    signal calc_req_valid        : std_logic;
    signal calc_pool_ready       : std_logic;
    signal calc_fc_pixel         : WORD;
    signal calc_fc_valid         : std_logic;
    signal calc_curr_index       : integer range 0 to FC1_NODES_IN-1;
    signal calc_done             : std_logic;

    -- Signals for FC1 output
    signal fc1_out_valid         : std_logic;
    signal fc1_out_data          : WORD_ARRAY(0 to FC1_NODES_OUT-1);
    signal fc1_in_ready          : std_logic;
    
    -- Signals for FC2 input (from sequencer)
    signal fc2_input_index       : integer range 0 to FC1_NODES_OUT-1 := 0;
    signal fc2_input_valid       : std_logic;
    signal fc2_input_data        : WORD;
    
    -- Signals for FC2 output
    signal fc2_out_valid         : std_logic;
    signal fc2_out_data          : WORD_ARRAY(0 to FC2_NODES_OUT-1);
    signal fc2_in_ready          : std_logic;

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
            
            -- Request FROM external controller OR calc_index (muxed)
            pixel_out_req_row   => calc_req_row when use_fc_path = '1' else output_req_row,
            pixel_out_req_col   => calc_req_col when use_fc_path = '1' else output_req_col,
            pixel_out_req_valid => calc_req_valid when use_fc_path = '1' else output_req_valid,
            pixel_out_req_ready => open,  -- Not used

            -- Request TO conv2
            pixel_in_req_row    => pool2_in_req_row,
            pixel_in_req_col    => pool2_in_req_col,
            pixel_in_req_valid  => pool2_in_req_valid,
            pixel_in_req_ready  => pool2_in_req_ready,

            -- Data FROM conv2
            pixel_in            => conv2_pixel_out,
            pixel_in_valid      => conv2_pixel_out_valid,
            pixel_in_ready      => conv2_pixel_out_ready,

            -- Data output
            pixel_out           => pool2_pixel_out,
            pixel_out_valid     => pool2_pixel_out_valid,
            pixel_out_ready     => calc_pool_ready when use_fc_path = '1' else output_ready
        );

    -- Connect pool2 output requests to conv2 input requests
    conv2_out_req_row   <= pool2_in_req_row;
    conv2_out_req_col   <= pool2_in_req_col;
    conv2_out_req_valid <= pool2_in_req_valid;
    pool2_in_req_ready  <= conv2_out_req_ready;
    
    -- Route Pool2 outputs directly to top-level ports
    output_pixel <= pool2_pixel_out;
    output_valid <= pool2_pixel_out_valid;
    output_req_ready <= '1';  -- Always ready to accept requests
    
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
            pool_pixel_data  => pool2_pixel_out,
            pool_pixel_valid => pool2_pixel_out_valid,
            pool_pixel_ready => calc_pool_ready,
            
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
            
            -- Output (directly to FC2 sequencer, no buffer)
            pixel_out_valid => fc1_out_valid,
            pixel_out_data  => fc1_out_data
        );

    -- Sequencer: Convert FC1's parallel output to sequential stream for FC2
    fc_seq_inst: entity work.fc_sequencer
        generic map (
            NUM_NEURONS => FC1_NODES_OUT  -- 64
        )
        port map (
            clk          => clk,
            rst          => rst,
            
            -- Parallel input FROM FC1
            input_valid  => fc1_out_valid,
            input_data   => fc1_out_data,
            
            -- Sequential output TO FC2
            output_valid => fc2_input_valid,
            output_ready => fc2_in_ready,
            output_data  => fc2_input_data,
            output_index => fc2_input_index
        );

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
            
            -- Output
            pixel_out_valid => fc2_out_valid,
            pixel_out_data  => fc2_out_data
        );

    -- Connect FC1 output to top-level ports
    fc1_output_data  <= fc1_out_data;
    fc1_output_valid <= fc1_out_valid;
    
    -- Connect FC2 output to top-level ports
    fc2_output_data  <= fc2_out_data;
    fc2_output_valid <= fc2_out_valid;
    
    -- Placeholder for output_guess (will be driven by argmax)
    output_guess  <= (others => '0');
    
    -- DEBUG: Export calc_index signals
    debug_calc_index <= calc_curr_index;
    debug_calc_pixel <= calc_fc_pixel;
    debug_calc_valid <= calc_fc_valid;
    debug_calc_done  <= calc_done;

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

    -- Pool2 output tap (for debugging FC path)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                debug_pool2_pixel <= (others => (others => '0'));
                debug_pool2_valid <= '0';
                debug_pool2_row <= 0;
                debug_pool2_col <= 0;
            else
                -- Just tap the signals directly
                debug_pool2_pixel <= pool2_pixel_out;
                debug_pool2_valid <= pool2_pixel_out_valid;
                -- Capture the request position
                if use_fc_path = '1' then
                    debug_pool2_row <= calc_req_row;
                    debug_pool2_col <= calc_req_col;
                else
                    debug_pool2_row <= output_req_row;
                    debug_pool2_col <= output_req_col;
                end if;
            end if;
        end if;
    end process;

end Structural;
