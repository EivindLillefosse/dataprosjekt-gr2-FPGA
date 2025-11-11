----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.04.2025
-- Design Name: Fully Connected Layer
-- Module Name: fc_layer - Behavioral
-- Project Name: CNN Accelerator
-- Description: Modular fully connected layer using separate components
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;
use work.bias_pkg.all;

entity fc_layer is
    generic (
        NODES_IN  : integer := 400;
        NODES_OUT : integer := 64;
        LAYER_ID  : integer := 0
    );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        enable: in  std_logic;
        
        -- Input interface
        input_valid : in  std_logic;
        input_pixel : in  WORD;
        input_index : in  integer range 0 to NODES_IN-1;
        input_ready : out std_logic;
        
        -- Output interface
        output_valid : out std_logic;
        output_pixel : out WORD_ARRAY(0 to NODES_OUT-1);
        output_ready : in  std_logic;
        
        layer_done   : out std_logic
    );
end fc_layer;

architecture Behavioral of fc_layer is

    -- Internal connection signals
    
    -- Controller signals
    signal calc_clear      : std_logic;
    signal calc_compute_en : std_logic;
    signal ctrl_output_valid : std_logic;
    
    -- Weight memory signals
    signal weight_data : WORD_ARRAY(0 to NODES_OUT-1);
    
    -- Calculation module signals
    signal calc_results    : WORD_ARRAY_16(0 to NODES_OUT-1);
    signal calc_done       : std_logic_vector(NODES_OUT-1 downto 0);
    
    -- Bias registers and biased result signals
    type bias_local_t is array (natural range <>) of signed(7 downto 0);
    signal bias_regs : bias_local_t(0 to NODES_OUT-1);
    signal biased_results : WORD_ARRAY_16(0 to NODES_OUT-1);
    
    -- Q-format scaling signals (Q2.12 -> Q1.6)
    signal scaler_valid_in  : std_logic;
    signal scaler_data_out  : WORD_ARRAY(0 to NODES_OUT-1);
    signal scaler_valid_out : std_logic;
    
    -- ReLU activation signals
    signal relu_data_out  : WORD_ARRAY(0 to NODES_OUT-1);
    signal relu_valid_out : std_logic;

begin

    -- Weight Memory Controller
    weight_mem_ctrl : entity work.fc_memory_controller
        generic map (
            NUM_NODES  => NODES_OUT,
            NUM_INPUTS => NODES_IN,
            LAYER_ID   => LAYER_ID
        )
        port map (
            clk         => clk,
            pixel_index => input_index,
            weight_data => weight_data
        );

    -- Calculation Module (MAC array)
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
            pixel_data   => input_pixel,
            weight_data  => weight_data,
            compute_en   => calc_compute_en,
            results      => calc_results,
            compute_done => calc_done
        );

    -- Drive bias_regs from the appropriate package constant using generate
    gen_bias_layer5 : if LAYER_ID = 0 generate
        bias_assign0 : for i in 0 to NODES_OUT-1 generate
            bias_regs(i) <= resize(layer_5_dense_BIAS(i), 8);
        end generate;
    end generate;

    gen_bias_layer6 : if LAYER_ID = 1 generate
        bias_assign1 : for i in 0 to NODES_OUT-1 generate
            bias_regs(i) <= resize(layer_6_dense_1_BIAS(i), 8);
        end generate;
    end generate;

    -- Elaboration-time checks: ensure NODES_OUT matches package bias sizes
    gen_check_layer5 : if LAYER_ID = 0 generate
    begin
        assert NODES_OUT = layer_5_dense_BIAS'length
            report "fc_layer: NODES_OUT must equal layer_5_dense_BIAS length when LAYER_ID=0" severity failure;
    end generate;
    
    gen_check_layer6 : if LAYER_ID = 1 generate
    begin
        assert NODES_OUT = layer_6_dense_1_BIAS'length
            report "fc_layer: NODES_OUT must equal layer_6_dense_1_BIAS length when LAYER_ID=1" severity failure;
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

    -- Q-Format Scaler: Q2.12 -> Q1.6
    -- Scales down the biased results before ReLU activation
    q_scale : entity work.q_scaler
        generic map (
            NUM_CHANNELS => NODES_OUT,
            INPUT_WIDTH  => 16,  -- Q2.12
            OUTPUT_WIDTH => 8,   -- Q1.6
            SHIFT_AMOUNT => 6    -- 12 - 6 = 6 bits to shift
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => biased_results,
            valid_in  => scaler_valid_in,
            data_out  => scaler_data_out,
            valid_out => scaler_valid_out
        );

    -- ReLU Activation Layer (takes scaled Q1.6 results)
    relu : entity work.relu_layer
        generic map (
            NUM_FILTERS => NODES_OUT,
            DATA_WIDTH  => 8
        )
        port map (
            clk        => clk,
            rst        => rst,
            data_in    => scaler_data_out,
            data_valid => scaler_valid_out,
            data_out   => relu_data_out,
            valid_out  => relu_valid_out
        );

    -- Main Controller FSM
    controller : entity work.fc_controller
        generic map (
            NODES_IN  => NODES_IN,
            NODES_OUT => NODES_OUT,
            LAYER_ID  => LAYER_ID
        )
        port map (
            clk             => clk,
            rst             => rst,
            input_valid     => input_valid,
            input_index     => input_index,
            calc_clear      => calc_clear,
            calc_compute_en => calc_compute_en,
            output_valid    => ctrl_output_valid,
            input_ready     => input_ready
        );

    -- Connect scaler control signals
    scaler_valid_in <= ctrl_output_valid;
    
    -- Connect outputs
    output_pixel <= relu_data_out;
    output_valid <= relu_valid_out;
    layer_done <= relu_valid_out;  -- Layer done when final output is valid

end Behavioral;
