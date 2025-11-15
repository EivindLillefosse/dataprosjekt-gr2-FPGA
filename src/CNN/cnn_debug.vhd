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

        -- Request TO input provider (what input positions we need)
        input_req_row    : out integer;
        input_req_col    : out integer;
        input_req_valid  : out std_logic;
        input_req_ready  : in  std_logic;

        -- Data FROM input provider
        input_pixel      : in  WORD_ARRAY_16(0 to CONV_1_INPUT_CHANNELS-1);
        input_valid      : in  std_logic;
        input_ready      : out std_logic;

        -- Data TO external consumer (final output)
        output_valid     : out std_logic;
        output_ready     : in  std_logic;
        output_guess     : out WORD;  -- Final classification (placeholder)
        
        -- Control: (removed) Pool2 now always controlled by calc_index (FC) path
            
        -- FC1 outputs (for testing/debug)
        fc1_output_data  : out WORD_ARRAY_16(0 to 63);
        fc1_output_valid : out std_logic;
        -- FC1 ready is driven by the internal buffer (exported for TB visibility)
        fc1_output_ready : out std_logic;
        
        -- FC2 outputs (final 10-class classification)
        fc2_output_data  : out WORD_ARRAY_16(0 to 9);
        fc2_output_valid : out std_logic;
        fc2_output_ready : in  std_logic;

        -- DEBUG: Intermediate layer outputs
        -- Conv1 output (after convolution, before pool1)
        debug_conv1_pixel       : out WORD_ARRAY_16(0 to CONV_1_NUM_FILTERS-1);
        debug_conv1_valid       : out std_logic;
        debug_conv1_ready       : in  std_logic;
        debug_conv1_row         : out integer;
        debug_conv1_col         : out integer;
        
        -- Pool1 output (after first pooling, before conv2)
        debug_pool1_pixel       : out WORD_ARRAY_16(0 to CONV_1_NUM_FILTERS-1);
        debug_pool1_valid       : out std_logic;
        debug_pool1_ready       : in  std_logic;
        debug_pool1_row         : out integer;
        debug_pool1_col         : out integer;
        
        -- Conv2 output (after second convolution, before pool2)
        debug_conv2_pixel       : out WORD_ARRAY_16(0 to CONV_2_NUM_FILTERS-1);
        debug_conv2_valid       : out std_logic;
        debug_conv2_ready       : in  std_logic;
        debug_conv2_row         : out integer;
        debug_conv2_col         : out integer;
        
        -- Pool2 output (after second pooling, before FC layers)
        debug_pool2_pixel       : out WORD_ARRAY_16(0 to CONV_2_NUM_FILTERS-1);
        debug_pool2_valid       : out std_logic;
        debug_pool2_ready       : in  std_logic;
        debug_pool2_row         : out integer;
        debug_pool2_col         : out integer;
        
        -- DEBUG: calc_index status
        debug_calc_index        : out integer range 0 to 399;
        debug_calc_pixel        : out WORD_16;
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
    
    signal conv1_pixel_out      : WORD_ARRAY_16(0 to CONV_1_NUM_FILTERS-1);
    signal conv1_pixel_out_valid: std_logic;
    signal conv1_pixel_out_ready: std_logic;
    
    signal conv1_pixel_in       : WORD_ARRAY_16(0 to CONV_1_INPUT_CHANNELS-1);
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
    
    signal pool1_pixel_out      : WORD_ARRAY_16(0 to CONV_1_NUM_FILTERS-1);
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
    
    signal conv2_pixel_out      : WORD_ARRAY_16(0 to CONV_2_NUM_FILTERS-1);
    signal conv2_pixel_out_valid: std_logic;
    signal conv2_pixel_out_ready: std_logic;

    -- Signals between pool2 and output (request/response protocol)
    signal pool2_in_req_row     : integer;
    signal pool2_in_req_col     : integer;
    signal pool2_in_req_valid   : std_logic;
    signal pool2_in_req_ready   : std_logic;
    
    -- Pool2 output signals
    signal pool2_pixel_out       : WORD_ARRAY_16(0 to CONV_2_NUM_FILTERS-1);
    signal pool2_pixel_out_valid : std_logic;
    signal pool2_pixel_out_ready : std_logic;
    
    -- Signals between calc_index and fc1
    signal calc_index_enable     : std_logic;
    signal calc_req_row          : integer;
    signal calc_req_col          : integer;
    signal calc_req_valid        : std_logic;
    signal calc_pool_ready       : std_logic;
    signal calc_fc_pixel         : WORD_16;
    signal calc_fc_valid         : std_logic;
    signal calc_curr_index       : integer range 0 to FC1_NODES_IN-1;
    signal calc_done             : std_logic;

    -- Signals for FC1 output
    signal fc1_out_valid         : std_logic;
    signal fc1_out_data          : WORD_ARRAY_16(0 to FC1_NODES_OUT-1);
    signal fc1_in_ready          : std_logic;

    -- Signals for sequencer between FC1 and FC2
    signal seq_input_valid       : std_logic;
    signal seq_input_ready       : std_logic;
    signal seq_input_data        : WORD_ARRAY_16(0 to FC1_NODES_OUT-1);
    
    signal seq_output_valid      : std_logic;
    signal seq_output_ready      : std_logic;
    signal seq_output_data       : WORD_16;
    signal seq_output_index      : integer range 0 to FC1_NODES_OUT-1;
    
    -- Signals for FC2 output
    signal fc2_out_valid         : std_logic;
    signal fc2_out_data          : WORD_ARRAY_16(0 to FC2_NODES_OUT-1);
    signal fc2_in_ready          : std_logic;
    -- Registered output guess (persist across resets until overwritten)
    signal output_guess_reg : WORD := (others => '0');

    -- DEBUG: Register output positions when request handshake completes
    signal conv1_active_out_row : integer := 0;
    signal conv1_active_out_col : integer := 0;
    signal pool1_active_out_row : integer := 0;
    signal pool1_active_out_col : integer := 0;
    signal conv2_active_out_row : integer := 0;
    signal conv2_active_out_col : integer := 0;
    -- Previous valid register for one-cycle debug pulse
    signal prev_conv2_valid     : std_logic := '0';

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
            
            -- Request FROM calc_index (FC path)
            pixel_out_req_row   => calc_req_row,
            pixel_out_req_col   => calc_req_col,
            pixel_out_req_valid => calc_req_valid,
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

            -- Data output (FC path)
            pixel_out           => pool2_pixel_out,
            pixel_out_valid     => pool2_pixel_out_valid,
            pixel_out_ready     => calc_pool_ready
        );

    -- Connect pool2 output requests to conv2 input requests
    conv2_out_req_row   <= pool2_in_req_row;
    conv2_out_req_col   <= pool2_in_req_col;
    conv2_out_req_valid <= pool2_in_req_valid;
    pool2_in_req_ready  <= conv2_out_req_ready;
    
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
            enable          => '1',  -- Always enabled
            
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
            fc_pixel_ready  => fc1_in_ready,
            
            curr_index      => calc_curr_index,
            done            => calc_done
        );

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
            
            -- Output TO sequencer
            pixel_out_valid => fc1_out_valid,
            pixel_out_ready => seq_input_ready,
            pixel_out_data  => fc1_out_data
        );

    -- Sequencer between FC1 and FC2
    fc_sequencer: entity work.fc_sequencer
        generic map (
            NUM_NEURONS => FC1_NODES_OUT  -- 64
        )
        port map (
            clk          => clk,
            rst          => rst,
            
            -- Input FROM FC1
            input_valid  => seq_input_valid,
            input_ready  => seq_input_ready,
            input_data   => seq_input_data,
            
            -- Output TO FC2
            output_valid => seq_output_valid,
            output_ready => seq_output_ready,
            output_data  => seq_output_data,
            output_index => seq_output_index
        );

    -- =====================================================================
    -- Interconnect: FC1 -> Sequencer
    -- =====================================================================
    seq_input_valid <= fc1_out_valid;
    seq_input_data  <= fc1_out_data;

    -- =====================================================================
    -- Interconnect: Sequencer -> FC2
    -- =====================================================================
    -- (Already connected via port maps above)

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
            
            -- Input FROM sequencer
            pixel_in_valid  => seq_output_valid,
            pixel_in_ready  => seq_output_ready,
            pixel_in_data   => seq_output_data,
            pixel_in_index  => seq_output_index,
            
            -- Output (FC2 doesn't use input ready signal)
            pixel_out_valid => fc2_out_valid,
            pixel_out_ready => fc2_output_ready,
            pixel_out_data  => fc2_out_data
        );

    -- Connect FC1 output to top-level ports
    fc1_output_data  <= fc1_out_data;
    fc1_output_valid <= fc1_out_valid;
    -- Expose internal sequencer input-ready as the top-level FC1 ready signal
    fc1_output_ready <= seq_input_ready;
    
    -- Connect FC2 output to top-level ports
    fc2_output_data  <= fc2_out_data;
    fc2_output_valid <= fc2_out_valid;
    
    -- Output guess is driven from registered storage (declared above)
    output_guess <= output_guess_reg;
    -- Drive the simplified top-level output_valid from the internal FC2 valid
    output_valid  <= fc2_out_valid;
    
    -- DEBUG: Export calc_index signals
    debug_calc_index <= calc_curr_index;
    debug_calc_pixel <= calc_fc_pixel;
    debug_calc_valid <= calc_fc_valid;
    debug_calc_done  <= calc_done;

    -- Update output_guess only when FC2 produces a new accepted result.
    -- Do NOT clear output_guess on reset; keep previous value unless new accepted result arrives.
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                output_guess_reg <= (others => '0');
            else
                if fc2_out_valid = '1' and fc2_output_ready = '1' then
                    output_guess_reg <= fc2_out_data(0)(7 downto 0);
                end if;
            end if;
        end if;
    end process;

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
    -- Pulse debug_conv2_valid for one cycle on the rising edge of conv2_pixel_out_valid
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                debug_conv2_pixel <= (others => (others => '0'));
                debug_conv2_valid <= '0';
                debug_conv2_row <= 0;
                debug_conv2_col <= 0;
                prev_conv2_valid <= '0';
            else
                -- detect rising edge
                if conv2_pixel_out_valid = '1' and prev_conv2_valid = '0' then
                    debug_conv2_pixel <= conv2_pixel_out;
                    debug_conv2_valid <= '1';
                    debug_conv2_row <= conv2_active_out_row;
                    debug_conv2_col <= conv2_active_out_col;
                else
                    debug_conv2_valid <= '0';
                end if;
                prev_conv2_valid <= conv2_pixel_out_valid;
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
                -- Just tap the signals directly and expose FC calc_index position
                debug_pool2_pixel <= pool2_pixel_out;
                debug_pool2_valid <= pool2_pixel_out_valid;
                -- Capture the FC request position (calc_index)
                debug_pool2_row <= calc_req_row;
                debug_pool2_col <= calc_req_col;
            end if;
        end if;
    end process;

end Structural;
