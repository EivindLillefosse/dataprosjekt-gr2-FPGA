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
        weight_data_valid : in  std_logic;
    -- (bias handled locally in top module)
                
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
        
        -- I/O control
        input_ready   : out std_logic;
        input_valid   : in  std_logic;
        output_valid  : out std_logic;
        output_ready  : in  std_logic;
        -- Indicates that scaling (and any pre-output processing) has completed
        scaled_done   : in  std_logic
    );
end convolution_controller;

architecture Behavioral of convolution_controller is

    type state_type is (IDLE, LOAD_WEIGHTS, WAIT_WEIGHTS, LOAD_DATA, COMPUTE, POST_COMPUTE, OUTPUT_WAIT);
    signal current_state : state_type := IDLE;
    
begin

    fsm_proc: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            weight_load_req <= '0';
            pos_advance <= '0';
            compute_en <= '0';
            compute_clear <= '0';
            input_ready <= '0';
            output_valid <= '0';
            
        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    compute_clear <= '0';
                    output_valid <= '0';
                    input_ready <= '0';
                    pos_advance <= '0';
                    
                    if enable = '1' then
                        current_state <= LOAD_WEIGHTS;
                    end if;

                when LOAD_WEIGHTS =>
                    -- request weight stream for current kernel position (all filters arrive together)
                    weight_load_req <= '1';
                    compute_en <= '0';
                    compute_clear <= '0';
                    input_ready <= '0';
                    output_valid <= '0';
                    pos_advance <= '0';

                    -- transition once the weight bundle for all filters is valid
                    if weight_data_valid = '1' then
                        weight_load_req <= '0';
                        current_state <= LOAD_DATA;
                    end if;

                when LOAD_DATA =>
                    weight_load_req <= '0';
                    compute_en <= '0';
                    compute_clear <= '0';
                    pos_advance <= '0';
                    output_valid <= '0';
                    
                    -- Signal ready to accept input pixel data
                    input_ready <= '1';
                    
                    if input_valid = '1' then
                        input_ready <= '0';
                        current_state <= COMPUTE;
                    end if;
                    
                when COMPUTE =>
                    compute_en <= '1';
                    -- Wait for MAC computation to complete
                    if compute_done = (compute_done'range => '1') then
                        compute_en <= '0';
                        -- move to post-compute bookkeeping (decide whether to output now or wait)
                        current_state <= POST_COMPUTE;
                    end if;

                when POST_COMPUTE =>
                    -- After compute completes: request output/scaling by asserting output_valid
                    compute_en <= '0';
                    input_ready <= '0';
                    -- set output_valid to request downstream scaling/processing
                    output_valid <= '1';
                    -- do not clear or advance yet; wait for scaled_done
                    compute_clear <= '0';
                    pos_advance <= '0';

                    if region_done = '1' then
                        -- If downstream is already ready, remain in POST_COMPUTE and wait for scaled_done
                        -- Otherwise, move to OUTPUT_WAIT to wait for ready & scaled_done
                        if output_ready = '1' then
                            -- keep asserting output_valid while waiting for scaled_done
                            if scaled_done = '1' then
                                -- now it's safe to clear and advance
                                compute_clear <= '1';
                                pos_advance <= '1';
                                output_valid <= '0';
                                if layer_done = '1' then
                                    current_state <= IDLE;
                                else
                                    current_state <= LOAD_WEIGHTS;
                                end if;
                            end if;
                        else
                            current_state <= OUTPUT_WAIT;
                        end if;
                    else
                        -- Continue processing current region immediately
                        output_valid <= '0';
                        pos_advance <= '1';
                        current_state <= LOAD_WEIGHTS;
                    end if;

                when OUTPUT_WAIT =>
                    -- Wait for downstream readiness and scaled_done
                    compute_en <= '0';
                    input_ready <= '0';
                    output_valid <= '1'; -- keep requesting output/scaling
                    compute_clear <= '0';
                    pos_advance <= '0';
                    if output_ready = '1' and scaled_done = '1' then
                        -- scaling finished and consumer ready: finalize output
                        compute_clear <= '1';
                        pos_advance <= '1';
                        output_valid <= '0';

                        if layer_done = '1' then
                            current_state <= IDLE;
                        else
                            current_state <= LOAD_WEIGHTS;
                        end if;
                    end if;
        
                when others =>
                    current_state <= IDLE;
            end case;
        end if;
    end process;
    
    -- Connect position to weight controller
    weight_kernel_row <= region_row;
    weight_kernel_col <= region_col;

end Behavioral;