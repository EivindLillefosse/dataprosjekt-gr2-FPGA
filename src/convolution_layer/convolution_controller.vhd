----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Convolution Controller
-- Module Name: convolution_controller - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Main FSM controller for coordinating convolution components
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity convolution_controller is
    generic (
        NUM_FILTERS : integer := 8;
        KERNEL_SIZE : integer := 3
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        enable        : in  std_logic;
        
        -- Memory controller interface
        weight_load_req   : out std_logic;
        weight_kernel_row : out integer range 0 to KERNEL_SIZE-1;
        weight_kernel_col : out integer range 0 to KERNEL_SIZE-1;
        weight_channel    : out integer range 0 to NUM_FILTERS-1;
         
        -- (bias handled locally in conv top module)
                
        -- Position calculator interface  
        pos_advance   : out std_logic;
        region_row    : in  integer range 0 to KERNEL_SIZE-1;
        region_col    : in  integer range 0 to KERNEL_SIZE-1;
        region_done   : in  std_logic;
        layer_done    : in  std_logic;
        
        -- Convolution engine interface
        compute_en    : out std_logic;
        compute_clear : out std_logic;
        compute_done  : in  std_logic_vector(NUM_FILTERS-1 downto 0);

        -- Indicates that scaling (and any pre-output processing) has completed
        scaled_ready  : out std_logic;
        scaled_done   : in  std_logic;

        -- I/O control
        input_ready   : out std_logic;
        input_valid   : in  std_logic;
        output_valid  : out std_logic;
        output_ready  : in  std_logic
    );
end convolution_controller;

architecture Behavioral of convolution_controller is

    -- Add PIXEL_DONE state to generate a one-cycle compute_clear and pos_advance pulse
    type state_type is (IDLE, LOAD_WEIGHTS, WAIT_WEIGHTS, LOAD_DATA, COMPUTE, PIXEL_DONE, POST_COMPUTE, OUTPUT_WAIT);
    signal current_state : state_type := IDLE;
    signal next_state_sig    : state_type := IDLE;
    -- Registered outputs next-value signals
    signal weight_load_req_n : std_logic := '0';
    signal weight_channel_n  : integer range 0 to NUM_FILTERS-1 := 0;
    signal pos_advance_n     : std_logic := '0';
    signal compute_en_n      : std_logic := '0';
    signal compute_clear_n   : std_logic := '0';
    signal input_ready_n     : std_logic := '0';
    signal output_valid_n    : std_logic := '0';
    signal scaled_ready_n    : std_logic := '0';

    -- Helper: return true when all bits in a std_logic_vector are '1'
    function all_ones(vec : std_logic_vector) return boolean is
    begin
        for i in vec'range loop
            if vec(i) /= '1' then
                return false;
            end if;
        end loop;
        return true;
    end function;

begin

    -- Synchronous state register
    state_reg : process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state_sig;
        end if;
    end process;

    -- Combinational next-state and output logic (Moore-style outputs assigned here)
    fsm_comb : process(current_state, enable, input_valid, compute_done, region_done, output_ready, scaled_done, layer_done)
        -- Local variable for next state (named 'next_state')
        variable next_state : state_type := IDLE;
        -- Local combinational next-values for outputs
        variable v_pos_advance     : std_logic := '0';
        variable v_compute_en      : std_logic := '0';
        variable v_compute_clear   : std_logic := '0';
        variable v_input_ready     : std_logic := '0';
        variable v_output_valid    : std_logic := '0';
        variable v_scaled_ready    : std_logic := '0';
        variable v_current_channel : integer range 0 to NUM_FILTERS-1 := 0;
    begin

        -- Default next state is to remain; capture current state into variable
        next_state := current_state;

        -- Default outputs (variables) already '0'
        v_pos_advance := '0';

    case current_state is
            when IDLE =>
                -- stay idle until enabled
                if enable = '1' then
                    next_state := LOAD_WEIGHTS;
                end if;

            when LOAD_WEIGHTS =>
                -- request weight bundle
                next_state    := LOAD_DATA;

            when LOAD_DATA =>
                -- wait for input pixel
                v_input_ready := '1';
                if input_valid = '1' then
                    v_input_ready := '0';
                    v_compute_en := '1';
                    next_state := COMPUTE;
                    v_pos_advance := '1';
                end if;

            when COMPUTE =>
                -- compute_en is pulsed on the transition into COMPUTE (from LOAD_DATA)
                -- wait for the MAC/engine to assert compute_done, then proceed to POST_COMPUTE
                v_compute_en := '0';
                if all_ones(compute_done) then
                    if weight_channel < NUM_FILTERS-1 then
                        v_current_channel := 0;
                        next_state := POST_COMPUTE;
                    else
                        v_current_channel := v_current_channel + 1;
                        next_state := LOAD_WEIGHTS;
                    end if;
                end if;

            when POST_COMPUTE =>
                -- request downstream processing (scaling/ReLU)
                v_pos_advance  := '0';
                if region_done = '1' then
                    v_scaled_ready := '1';
                    next_state := PIXEL_DONE;
                else
                    -- continue current region
                    next_state := LOAD_WEIGHTS;
                end if;

            when PIXEL_DONE =>
                v_scaled_ready := '1';
                -- Pulse compute_clear and advance position for one cycle, then move to next region or layer
                v_compute_clear := '1';
                v_output_valid := '0';
                if scaled_done = '1' then
                    v_scaled_ready := '0';
                    v_compute_clear := '0';
                    -- Decide next state after the pixel-clear: if layer is done, go IDLE, else load next weights
                    if layer_done = '1' then
                        next_state := IDLE;
                    else
                        next_state := OUTPUT_WAIT;
                    end if;
                end if;
                        

            when OUTPUT_WAIT =>
                v_output_valid := '1';
                if output_ready = '1' then
                    v_output_valid := '0';
                    next_state := LOAD_WEIGHTS;
                end if;

            when others =>
                next_state := IDLE;
        end case;

        -- Commit local next-state variable to the signal
        next_state_sig <= next_state;

        -- Commit combinational next-values to registered next signals
        weight_channel_n  <= v_current_channel;
        pos_advance_n     <= v_pos_advance;
        compute_en_n      <= v_compute_en;
        compute_clear_n   <= v_compute_clear;
        input_ready_n     <= v_input_ready;
        output_valid_n    <= v_output_valid;
        scaled_ready_n    <= v_scaled_ready;
    end process;

    -- Output register: latch outputs on clock edge to remove combinational drivers
    outputs_reg : process(clk, rst)
    begin
        if rst = '1' then
            weight_load_req <= '0';
            weight_channel  <= 0;
            pos_advance     <= '0';
            compute_en      <= '0';
            compute_clear   <= '0';
            input_ready     <= '0';
            output_valid    <= '0';
            scaled_ready    <= '0';
        elsif rising_edge(clk) then
            weight_load_req <= weight_load_req_n;
            weight_channel  <= weight_channel_n;
            pos_advance     <= pos_advance_n;
            compute_en      <= compute_en_n;
            compute_clear   <= compute_clear_n;
            input_ready     <= input_ready_n;
            output_valid    <= output_valid_n;
            scaled_ready    <= scaled_ready_n;
        end if;
    end process;

    -- Connect position to weight controller
    weight_kernel_row <= region_row;
    weight_kernel_col <= region_col;

end Behavioral;