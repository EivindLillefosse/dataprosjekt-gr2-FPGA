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
        clk           : in  std_logic;
        rst           : in  std_logic;
        -- Input interface
        pixel_in_valid   : in  std_logic;   
        pixel_in_ready   : out std_logic;                  -- Input pixel is valid
        pixel_in_data    : in  WORD;                       -- Input pixel value (8 bits)
        pixel_in_index   : in  integer range 0 to  NODES_IN-1;     -- Position in input (0-399)
        -- Output interface
        pixel_out_valid   : out std_logic;                  -- Output pixel is valid
        pixel_out_ready   : out std_logic;                  -- All 64 outputs ready
        pixel_out_data    : out WORD_ARRAY(0 to NODES_OUT-1)        -- Output neurons after ReLU (8 bits each)
    );
end fullyconnected;

architecture RTL of fullyconnected is
    -- Signals for calculation module
    signal calc_clear      : std_logic;
    signal calc_pixel_data : std_logic_vector(WORD_SIZE-1 downto 0);
    signal calc_weights    : WORD_ARRAY(0 to NODES_OUT-1);
    signal calc_compute_en : std_logic;
    signal calc_results    : WORD_ARRAY_16(0 to NODES_OUT-1);
    signal calc_done       : std_logic_vector(NODES_OUT-1 downto 0);
    
    -- Signals for bias addition
    type bias_array_t is array (natural range <>) of signed(7 downto 0);
    signal bias_regs       : bias_array_t(0 to NODES_OUT-1);
    signal biased_results  : WORD_ARRAY_16(0 to NODES_OUT-1);
    
    -- Signals for ReLU
    signal relu_in_data    : WORD_ARRAY(0 to NODES_OUT-1);
    signal data_valid      : std_logic;
    signal data_out        : WORD_ARRAY(0 to NODES_OUT-1);
    signal valid_out       : std_logic;

begin

    -- Instantiate calculation module (64 MACs)
    calc_inst : entity work.calculation
        generic map (
            NODES            => NODES_OUT,
            MAC_DATA_WIDTH   => WORD_SIZE,
            MAC_RESULT_WIDTH => WORD_SIZE*2
        )
        port map (
            clk          => clk,
            rst          => rst,
            clear        => calc_clear,
            pixel_data   => calc_pixel_data,
            weight_data  => calc_weights,
            compute_en   => calc_compute_en,
            results      => calc_results,
            compute_done => calc_done
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
            NODES_IN   => NODES_IN,
            NODES_OUT  => NODES_OUT,
            LAYER_ID   => LAYER_ID
        )
        port map (
            clk           => clk,
            rst           => rst,
            input_valid   => pixel_in_valid,
            input_index   => pixel_in_index,
            calc_clear    => calc_clear,
            calc_compute_en => calc_compute_en,
            output_valid  => data_valid,
            input_ready   => pixel_in_ready
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

    -- Add bias to calculation results before ReLU
    -- CRITICAL: Convert bias from Q1.6 to Q2.12 before adding to calc results
    biased_results_proc: process(calc_results, bias_regs)
    begin
        for i in 0 to NODES_OUT-1 loop
            -- Add bias in Q2.12 format to calc_results (which are Q2.12)
            biased_results(i) <= std_logic_vector(signed(calc_results(i)) + resize(bias_regs(i), 16));
        end loop;
    end process;

    -- Scale biased results from Q2.12 to Q1.6 (8-bit) for ReLU
    gen_relu_input: for i in 0 to NODES_OUT-1 generate
        relu_in_data(i) <= biased_results(i)(15 downto 8);  -- Take middle 8 bits
    end generate;

    -- ReLU Activation Layer (takes scaled Q1.6 results)
    relu : entity work.relu_layer
        generic map (
            NUM_FILTERS => NODES_OUT,
            DATA_WIDTH => 8  
        )
        port map (
            clk => clk,
            rst => rst,
            data_in => relu_in_data,
            data_valid => data_valid,
            data_out => data_out,
            valid_out => valid_out
        );

    -- Connect ReLU output to module output
    pixel_out_data <= data_out;
    pixel_out_valid <= valid_out;
    pixel_out_ready <= valid_out;

end RTL;
