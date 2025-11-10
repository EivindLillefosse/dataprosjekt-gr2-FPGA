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
        FC1_NODES_OUT     : integer := 64
    
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
        output_guess     : out WORD;  -- Final classification (after argmax) - placeholder for now
        output_valid     : out std_logic;
        output_ready     : in  std_logic;
        
        -- FC1 outputs (intermediate, for testing/debug)
        fc1_output_data  : out WORD_ARRAY(0 to 63);  -- 64 outputs from FC1
        fc1_output_valid : out std_logic;
        fc1_output_ready : in  std_logic
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
            
            -- Output TO external consumer or FC2
            pixel_out_valid => fc1_out_valid,
            pixel_out_ready => fc1_out_ready,
            pixel_out_data  => fc1_out_data
        );

    -- Connect FC1 output to top-level output
    fc1_output_data  <= fc1_out_data;
    fc1_output_valid <= fc1_out_valid;
    fc1_out_ready    <= fc1_output_ready;  -- Connect ready from top-level port
    
    -- Placeholder for output_guess (will be driven by argmax after FC2 is added)
    output_guess  <= (others => '0');
    output_valid  <= fc1_out_valid;  -- Use FC1 valid for now

    -- Connect top-level input requests to conv1's input requests
    input_req_row    <= conv1_in_req_row;
    input_req_col    <= conv1_in_req_col;
    input_req_valid  <= conv1_in_req_valid;
    conv1_in_req_ready <= input_req_ready;

    -- Connect top-level input data to conv1's input data
    conv1_pixel_in       <= input_pixel;
    conv1_pixel_in_valid <= input_valid;
    input_ready          <= conv1_pixel_in_ready;

    -- TEMPORARY: Auto-request generator for synthesis testing
    -- Automatically cycles through all output positions to ensure complete synthesis
    auto_request_gen: process(clk)
        variable req_pending : boolean := false;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                output_req_row <= 0;
                output_req_col <= 0;
                output_req_valid <= '0';
                output_pixel_ready <= '0';
                auto_req_active <= '0';
                req_pending := false;
            else
                -- Default: clear request valid
                output_req_valid <= '0';
                output_pixel_ready <= '0';
                
                -- Start auto-requesting after reset (simple enable-free approach)
                if auto_req_active = '0' then
                    auto_req_active <= '1';
                    output_req_valid <= '1';
                    req_pending := true;
                end if;
                
                -- Handle request acknowledgement
                if req_pending and output_req_ready = '1' then
                    req_pending := false;
                end if;
                
                -- Accept output when valid
                if output_pixel_valid = '1' then
                    output_pixel_ready <= '1';
                    
                    -- Move to next position after accepting output
                    if output_req_col < FINAL_OUTPUT_SIZE - 1 then
                        output_req_col <= output_req_col + 1;
                    else
                        output_req_col <= 0;
                        if output_req_row < FINAL_OUTPUT_SIZE - 1 then
                            output_req_row <= output_req_row + 1;
                        else
                            output_req_row <= 0; -- Wrap around to continue cycling
                        end if;
                    end if;
                    
                    -- Send next request
                    if not req_pending then
                        output_req_valid <= '1';
                        req_pending := true;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- TEMPORARY: Tie-down adapter for output_guess (map pool2 output to top-level port)
    -- This allows synthesis without changing the cnn_top entity port signature
    -- XOR all 16 filters together to ensure synthesis doesn't optimize them away
    -- This forces all filters to be computed and prevents elimination of unused logic
    process(output_pixel)
        variable combined : std_logic_vector(7 downto 0);
    begin
        combined := output_pixel(0)(7 downto 0);
        for i in 1 to CONV_2_NUM_FILTERS-1 loop
            combined := combined xor output_pixel(i)(7 downto 0);
        end loop;
        output_guess <= combined;
    end process;
    
    output_valid <= output_pixel_valid;
    -- output_ready is a top-level input port - don't drive output_pixel_ready from it
    -- The auto_request_gen process handles output_pixel_ready internally

end Structural;
