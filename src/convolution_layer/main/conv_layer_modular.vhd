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
use work.bias_pkg.all;

entity conv_layer_modular is
    generic (
        IMAGE_SIZE     : integer := 28;
        KERNEL_SIZE    : integer := 3;
        INPUT_CHANNELS : integer := 1;
        NUM_FILTERS    : integer := 8;
        STRIDE         : integer := 1;
        BLOCK_SIZE     : integer := 2;
        LAYER_ID       : integer := 0
    );
    Port ( 
        clk            : in STD_LOGIC;
        rst            : in STD_LOGIC;

        -- Request FROM downstream (what output position is needed)
        pixel_out_req_row   : in  integer;                             -- Requested output row
        pixel_out_req_col   : in  integer;                             -- Requested output col
        pixel_out_req_valid : in  std_logic;                           -- Output position request valid
        pixel_out_req_ready : out std_logic;                           -- Ready to accept output request

        -- Request TO upstream (what input positions we need)
        pixel_in_req_row    : out integer;                             -- Requesting input row
        pixel_in_req_col    : out integer;                             -- Requesting input col
        pixel_in_req_valid  : out std_logic;                           -- Input position request valid
        pixel_in_req_ready  : in  std_logic;                           -- Upstream ready for request

        -- Data FROM upstream (input pixels)
        -- For LAYER_ID=0: Use lower 8 bits of each 16-bit word
        -- For LAYER_ID=1: Use full 16 bits
        pixel_in            : in  WORD_ARRAY_16(0 to INPUT_CHANNELS-1);   -- Input pixel data (16-bit for flexibility)
        pixel_in_valid      : in  std_logic;                           -- Input data valid
        pixel_in_ready      : out std_logic;                           -- Ready to accept input data

        -- Data TO downstream (output result)
        pixel_out           : out WORD_ARRAY_16(0 to NUM_FILTERS-1);     -- Output pixel data
        pixel_out_valid     : out std_logic;                           -- Output data valid
        pixel_out_ready     : in  std_logic                            -- Downstream ready for data
    );
end conv_layer_modular;

architecture Behavioral of conv_layer_modular is
    constant INPUT_WIDTH : integer := 16;
    
    -- Flattened pixel data for convolution engine
    signal pixel_in_flat : std_logic_vector(INPUT_CHANNELS * INPUT_WIDTH - 1 downto 0);

    -- Internal connection signals
    
    -- Weight memory controller signals
    signal weight_load_req   : std_logic;
    signal weight_kernel_row : integer range 0 to KERNEL_SIZE-1;
    signal weight_kernel_col : integer range 0 to KERNEL_SIZE-1;
    signal weight_channel    : integer range 0 to INPUT_CHANNELS-1 := 0;
    signal weight_data       : WORD_ARRAY(0 to NUM_FILTERS-1);
    
    -- Position calculator signals
    signal pos_advance    : std_logic;
    signal current_row    : integer;
    signal current_col    : integer;
    signal input_row      : integer;
    signal input_col      : integer;
    signal region_row     : integer range 0 to KERNEL_SIZE-1;
    signal region_col     : integer range 0 to KERNEL_SIZE-1;
    signal region_done    : std_logic;
    signal pos_layer_done : std_logic;
    
    -- Store requested output position
    signal requested_out_row : integer := 0;
    signal requested_out_col : integer := 0;
    signal output_req_accepted : std_logic := '0';
    signal pos_req_pulse : std_logic := '0';  -- Single-cycle pulse for position calculator
    
    -- Convolution engine signals
    signal compute_en : std_logic;
    signal compute_clear : std_logic;
    signal compute_done : std_logic_vector(NUM_FILTERS-1 downto 0);
    signal conv_results : WORD_ARRAY_32(0 to NUM_FILTERS-1);
    
    -- ReLU activation signals
    signal relu_data_out : WORD_ARRAY_16(0 to NUM_FILTERS-1); 
    signal relu_valid_out : std_logic;

    -- Bias registers and biased result signals (local flexible type sized by NUM_FILTERS)
    type bias_local_t is array (natural range <>) of signed(7 downto 0);
    signal bias_regs : bias_local_t(0 to NUM_FILTERS-1);
    signal biased_results : WORD_ARRAY_16(0 to NUM_FILTERS-1);
    signal biased_valid : std_logic;
    -- Input to the ReLU block: biased_results shifted right by 6 (convert to Q1.6)
    signal relu_input : WORD_ARRAY_16(0 to NUM_FILTERS-1);

    -- Internal signal to capture controller's notion of output_valid (not used to drive module output)
    signal ctrl_output_valid : std_logic := '0';

    -- Biases are provided by bias_pkg (generated from Python export)

begin

    -- Flatten input pixels for convolution engine based on layer width
    flatten_inputs: for i in 0 to INPUT_CHANNELS-1 generate
        pixel_in_flat((i+1)*INPUT_WIDTH-1 downto i*INPUT_WIDTH) <= pixel_in(i);
    end generate;

    -- Handle output position requests from downstream
    -- When downstream requests an output position, store it and let the position calculator
    -- iterate through the 3×3 kernel window for that position
    output_request_handler: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pixel_out_req_ready <= '0';
                output_req_accepted <= '0';
                requested_out_row <= 0;
                requested_out_col <= 0;
                pos_req_pulse <= '0';
            else
                -- Default: not ready for new requests, no pulse
                pixel_out_req_ready <= '0';
                pos_req_pulse <= '0';
                
                -- Accept output position requests when not currently processing
                if pixel_out_req_valid = '1' and output_req_accepted = '0' then
                    pixel_out_req_ready <= '1';  -- Single-cycle acknowledgement pulse
                    requested_out_row <= pixel_out_req_row;
                    requested_out_col <= pixel_out_req_col;
                    output_req_accepted <= '1';
                    pos_req_pulse <= '1';  -- Single-cycle pulse to position calculator
                end if;
                
                -- Clear flag when output is complete and downstream has accepted it
                if pixel_out_valid = '1' and pixel_out_ready = '1' then
                    output_req_accepted <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- Generate input position requests based on output position + kernel offset
    -- This tells upstream what input pixel we need
    pixel_in_req_valid <= pixel_in_ready;  -- Request input whenever controller is ready

    -- Weight Memory Controller
    -- Use the entity's default generics (they match the module defaults),
    -- and explicitly map the ports. This avoids parser confusion in some
    -- tool versions when mixing generic/port maps across files.
    weight_mem_ctrl : entity work.weight_memory_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            NUM_INPUT_CHANNELS => INPUT_CHANNELS,
            KERNEL_SIZE => KERNEL_SIZE,
            LAYER_ID    => LAYER_ID
        )
        port map (
            clk        => clk,
            kernel_row => weight_kernel_row,
            kernel_col => weight_kernel_col,
            channel    => weight_channel,
            weight_data=> weight_data
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
            req_out_row => requested_out_row,
            req_out_col => requested_out_col,
            req_valid => pos_req_pulse,
            row => current_row,
            col => current_col,
            input_row => input_row,
            input_col => input_col,
            region_row => region_row,
            region_col => region_col,
            region_done => region_done,
            layer_done => pos_layer_done
        );

    -- Convolution Engine
    conv_engine : entity work.convolution_engine
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            INPUT_CHANNELS => INPUT_CHANNELS,
            MAC_DATA_WIDTH => INPUT_WIDTH,
            MAC_RESULT_WIDTH => INPUT_WIDTH*2
        )
        port map (
            clk => clk,
            rst => rst,
            clear => compute_clear,
            pixel_data => pixel_in_flat,
            channel_index => weight_channel,
            weight_data => weight_data,
            compute_en => compute_en,
            results => conv_results,
            compute_done => compute_done
        );


    -- Drive bias_regs from the appropriate package constant using generate (handles differing sizes)
    gen_bias_layer0 : if LAYER_ID = 0 generate
        bias_assign0 : for i in 0 to NUM_FILTERS-1 generate
            bias_regs(i) <= resize(layer_0_conv2d_BIAS(i), 8);
        end generate;
    end generate;

    gen_bias_layer2 : if LAYER_ID = 1 generate
        bias_assign2 : for i in 0 to NUM_FILTERS-1 generate
            bias_regs(i) <= resize(layer_2_conv2d_1_BIAS(i), 8);
        end generate;
    end generate;

    -- Elaboration-time checks: ensure NUM_FILTERS matches package bias sizes for chosen LAYER_ID
    gen_check_layer0 : if LAYER_ID = 0 generate
    begin
        assert NUM_FILTERS = layer_0_conv2d_BIAS'length
            report "conv_layer_modular: NUM_FILTERS must equal layer_0_conv2d_BIAS length when LAYER_ID=0" severity failure;
    end generate;
    gen_check_layer2 : if LAYER_ID = 1 generate
    begin
        assert NUM_FILTERS = layer_2_conv2d_1_BIAS'length
            report "conv_layer_modular: NUM_FILTERS must equal layer_2_conv2d_1_BIAS length when LAYER_ID=1" severity failure;
    end generate;

    -- Drive relu_input from biased_results using a generate (portable VHDL)
    -- Only instantiate the shifting logic for the layers that use 16-bit biased_results (LAYER_ID = 1)
    gen_relu_input_layer1 : if LAYER_ID = 1 generate
        gen_relu_input : for i in 0 to NUM_FILTERS-1 generate
        begin
            -- Optionally add rounding: shift_right(signed(biased_results(i)) + to_signed(32, 32), 6)
            relu_input(i) <= std_logic_vector( resize( shift_right( signed(conv_results(i)), 6 ), 16 ) );
        end generate;
    end generate;

    -- Fallback: for other layer IDs (e.g. LAYER_ID = 0) drive relu_input from biased_results
    -- scaled/converted appropriately or default to zero to avoid undriven signals. Here we
    -- simply map the lower 8 bits into the 16-bit word for LAYER_ID = 0 so the signal remains
    -- well-defined. Adjust if a different behavior is required.
    gen_relu_input_other : if LAYER_ID = 0 generate
        gen_relu_input_other_loop : for i in 0 to NUM_FILTERS-1 generate
            relu_input(i) <= std_logic_vector( resize( signed(conv_results(i)(7 downto 0)), 16) );
        end generate;
    end generate;

    -- Add bias to convolution results before ReLU
    -- CRITICAL: Convert bias from Q1.6 to Q2.12 before adding to conv results
    biased_results_proc: process(relu_input, bias_regs)
    begin
        for i in 0 to NUM_FILTERS-1 loop
            -- Then add bias in Q1.6 format to get final Q2.12 biased result
            biased_results(i) <= std_logic_vector(signed(relu_input(i)) + resize(bias_regs(i), 16));
        end loop;
    end process;


    -- ReLU Activation Layer (takes 16-bit inputs in Q1.6)
    relu : entity work.relu_layer
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            DATA_WIDTH => 16  -- Changed from 8 to 16
        )
        port map (
            clk => clk,
            rst => rst,
            data_in => biased_results,
            data_valid => biased_valid,
            data_out => relu_data_out,
            valid_out => relu_valid_out
        );

    controller : entity work.convolution_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            KERNEL_SIZE => KERNEL_SIZE,
            -- provide number of input channels so the controller can iterate channels
            NUM_INPUT_CHANNELS => INPUT_CHANNELS
        )
        port map (
            clk => clk,
            rst => rst,
            enable => output_req_accepted,  -- Only enable controller when we have an active request

            -- Weight memory controller
            weight_load_req => weight_load_req,
            weight_kernel_row => weight_kernel_row,
            weight_kernel_col => weight_kernel_col,
            weight_channel => weight_channel,

            -- Input interface (mapped to new request/response signals)
            input_ready => pixel_in_ready,
            input_valid => pixel_in_valid,

            -- Position calculator interface
            pos_advance => pos_advance,
            region_row => region_row,
            region_col => region_col,
            region_done => region_done,
            layer_done => pos_layer_done,
            
            -- Convolution engine interface
            compute_en => compute_en,
            compute_clear => compute_clear,
            compute_done => compute_done,

            -- Biased results ready signal
            scaled_ready => biased_valid,
            scaled_done  => relu_valid_out,

            -- Output interface (mapped to new request/response signals)
            output_valid => ctrl_output_valid,
            output_ready => pixel_out_ready
        );

    -- Connect position calculation outputs
    -- Position calculator now directly provides the absolute input positions
    -- (output position + kernel offset calculated internally)
    pixel_in_req_row <= input_row;
    pixel_in_req_col <= input_col;
    
    -- Connect outputs
    pixel_out <= relu_data_out;
    -- Drive module pixel_out_valid from the ReLU producer (data-valid originates at relu)
    pixel_out_valid <= relu_valid_out;

end Behavioral;