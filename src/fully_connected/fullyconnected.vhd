----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 10.18.2025
-- Design Name: Fully Connected
-- Module Name: FullyConnected - RTL
-- Project Name: CNN Accelerator
-- Description: FC layer (400 inputs -> 64 outputs)
--              Retrieves weights, performs MAC for each output, applies ReLU
--              Processes 400 input pixels sequentially
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;
use work.bias_pkg.all;

entity fullyconnected is
    generic (
        NODES_IN  : integer := 400;
        NODES_OUT : integer := 64;
        LAYER_ID  : integer := 0
    );

    port (
        clk               : in  std_logic;
        rst               : in  std_logic;
        -- Input interface
        pixel_in_valid    : in  std_logic;   
        pixel_in_ready    : out std_logic;                         -- Input pixel is valid
        pixel_in_data     : in  WORD_16;                           -- Input pixel value (16 bits)
        pixel_in_index    : in  integer range 0 to  NODES_IN-1;    -- Position in input (0-399)
        -- Output interface
        pixel_out_valid   : out std_logic;                         -- Output pixel is valid
        pixel_out_ready   : in  std_logic;                         -- Downstream ready for outputs
        pixel_out_data    : out WORD_ARRAY_16(0 to NODES_OUT-1)    -- Output neurons after ReLU (16 bits each)
    );
end fullyconnected;

architecture RTL of fullyconnected is
    -- Signals for calculation module
    signal calc_clear      : std_logic;
    signal calc_pixel_data : WORD_16;
    signal calc_weights    : WORD_ARRAY(0 to NODES_OUT-1);
    signal calc_compute_en : std_logic;
    signal calc_results    : WORD_ARRAY_32(0 to NODES_OUT-1);
    signal calc_done       : std_logic_vector(NODES_OUT-1 downto 0);
    
    -- Signals for bias addition
    type bias_array_t is array (natural range <>) of signed(7 downto 0);
    signal bias_regs       : bias_array_t(0 to NODES_OUT-1);
    -- Prevent Vivado from optimizing away or merging this register; keep full vector
    signal biased_results  : WORD_ARRAY_16(0 to NODES_OUT-1);
    attribute keep : string;
    attribute keep of biased_results : signal is "true";
    attribute syn_keep : string;
    attribute syn_keep of biased_results : signal is "true";
    
    -- Signals for ReLU
    signal relu_in_data    : WORD_ARRAY_16(0 to NODES_OUT-1);
    signal data_valid      : std_logic;
    signal data_out        : WORD_ARRAY_16(0 to NODES_OUT-1);
    signal valid_out       : std_logic;
    -- Signals for optional argmax (used when LAYER_ID = 1)
    signal arg_done_s      : std_logic := '0';
    -- argmax returns a 9-bit index; store as unsigned(8 downto 0)
    signal arg_max_idx_s   : unsigned(8 downto 0) := (others => '0');
    signal fc2_pixel_out   : WORD_ARRAY_16(0 to NODES_OUT-1) := (others => (others => '0'));
    signal fc2_pixel_valid : std_logic := '0';

begin

    -- Instantiate calculation module (64 MACs)
    calc_inst : entity work.calculation
        generic map (
            NODES            => NODES_OUT,
            MAC_DATA_WIDTH   => WORD_SIZE*2, -- 16 bits input
            MAC_RESULT_WIDTH => WORD_SIZE*4  -- 16 bits output
        )
        port map (
            clk              => clk,
            rst              => rst,
            clear            => calc_clear,
            pixel_data       => calc_pixel_data,
            weight_data      => calc_weights,
            compute_en       => calc_compute_en,
            results          => calc_results,
            compute_done     => calc_done
        );


    -- Instantiate fulcon_memory_controller
    mem_ctrl_inst : entity work.fullcon_memory_controller
        generic map (
            NUM_NODES  => NODES_OUT,
            NUM_INPUTS => NODES_IN,
            LAYER_ID   => LAYER_ID
        )
        port map (
            clk         => clk,
            pixel_index => pixel_in_index,
            weight_data => calc_weights
        );

    -- Instantiate controller
    ctrl_inst : entity work.fullcon_controller
        generic map (
            NODES_IN        => NODES_IN,
            NODES_OUT       => NODES_OUT,
            LAYER_ID        => LAYER_ID
        )
        port map (
            clk             => clk,
            rst             => rst,
            input_valid     => pixel_in_valid,
            input_index     => pixel_in_index,
            argmax_done     => arg_done_s,
            calc_clear      => calc_clear,
            calc_compute_en => calc_compute_en,
            calc_done       => calc_done,
            output_valid    => data_valid,
            input_ready     => pixel_in_ready
        );

    -- Connect input pixel data to calculation module
    calc_pixel_data <= pixel_in_data;

    -- Drive bias_regs from the appropriate package constant using generate (handles differing sizes)
    gen_bias_layer5 : if LAYER_ID = 0 generate
        bias_assign0 : for i in 0 to NODES_OUT-1 generate
            bias_regs(i) <= resize(layer_5_dense_BIAS(i), 8);
        end generate;
    end generate;

    gen_bias_layer6 : if LAYER_ID = 1 generate
        bias_assign2 : for i in 0 to NODES_OUT-1 generate
            bias_regs(i) <= resize(layer_6_dense_1_BIAS(i), 8);
        end generate;
    end generate;

    -- First convert high-precision calculation results down to Q1.6 (16-bit)
    relu_input_proc: process(calc_results)
    begin
        for i in 0 to NODES_OUT-1 loop
            -- Shift right by 6 to convert from Q2.12 (or similar) to Q1.6
            relu_in_data(i) <= std_logic_vector( resize( shift_right( signed(calc_results(i)), 6 ), 16 ) );
        end loop;
    end process;

    -- Add bias to the converted results before ReLU (matches conv_layer_modular pattern)
    biased_results_proc: process(relu_in_data, bias_regs)
    begin
        for i in 0 to NODES_OUT-1 loop
            -- Perform arithmetic on signed types, then convert back to std_logic_vector
            biased_results(i) <= std_logic_vector( signed(relu_in_data(i)) + resize(bias_regs(i), 16) );
        end loop;
    end process;

    -- ReLU Activation Layer (takes scaled Q1.6 results)
    -- LAYER_ID = 0: FC1 (hidden layer) uses ReLU
    -- LAYER_ID = 1: FC2 (output layer) bypasses ReLU to output raw logits
    gen_with_relu : if LAYER_ID = 0 generate
        relu : entity work.relu_layer
            generic map (
                NUM_FILTERS => NODES_OUT,
                DATA_WIDTH => WORD_SIZE*2  
            )
            port map (
                clk => clk,
                rst => rst,
                data_in => biased_results,
                data_valid => data_valid,
                data_out => data_out,
                valid_out => valid_out
            );

    end generate;

    -- For FC2 (LAYER_ID = 1) use ARGMAX on biased results
    gen_without_relu : if LAYER_ID = 1 generate
        signal arg_result_latched : std_logic := '0';
    begin
        -- Keep internal data path so the raw logits remain available
        data_out <= biased_results;
        valid_out <= data_valid;

        -- Instantiate arg_max: start when biased results become valid
        arg_inst: entity work.arg_max
          generic map (
            N_INPUTS => NODES_OUT,
            DATA_W   => WORD_SIZE*2,
            IDX_W    => 9
          )
          port map (
            clk     => clk,
            rst     => rst,
            start   => data_valid,
            data_in => biased_results,
            done    => arg_done_s,
            max_idx => arg_max_idx_s
          );
          -- Drive outputs directly when argmax finishes: place index in element 0, zeros elsewhere
          pixel_out_valid <= arg_done_s;
          pixel_out_data  <= (0 => std_logic_vector(resize(arg_max_idx_s, 16)), others => (others => '0'));
    end generate;

    -- For LAYER_ID = 0 the outputs are driven by the ReLU path
    gen_outputs_layer0 : if LAYER_ID = 0 generate
        pixel_out_data  <= data_out;
        pixel_out_valid <= valid_out;
    end generate;

end RTL;
