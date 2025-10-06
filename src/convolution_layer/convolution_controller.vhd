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
        weight_filter_idx : out integer range 0 to NUM_FILTERS-1;
        weight_kernel_row : out integer range 0 to KERNEL_SIZE-1;
        weight_kernel_col : out integer range 0 to KERNEL_SIZE-1;
        weight_data_valid : in  std_logic;
        weight_load_done  : in  std_logic;
        
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
        output_ready  : in  std_logic
    );
end convolution_controller;

architecture Behavioral of convolution_controller is

    type state_type is (IDLE, LOAD_WEIGHTS, WAIT_WEIGHTS, LOAD_DATA, COMPUTE, FINISH);
    signal current_state : state_type := IDLE;
    
    signal current_filter : integer range 0 to NUM_FILTERS-1 := 0;

begin

    fsm_proc: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            current_filter <= 0;
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
                        current_filter <= 0;
                        current_state <= LOAD_WEIGHTS;
                    end if;

                when LOAD_WEIGHTS =>
                    -- Request weight data for current filter and position
                    weight_load_req <= '1';
                    weight_filter_idx <= current_filter;
                    current_state <= WAIT_WEIGHTS;

                when WAIT_WEIGHTS =>
                    weight_load_req <= '0';
                    if weight_load_done = '1' then
                        if current_filter < NUM_FILTERS - 1 then
                            current_filter <= current_filter + 1;
                            current_state <= LOAD_WEIGHTS;
                        else
                            current_filter <= 0;
                            current_state <= LOAD_DATA;
                        end if;
                    end if;

                when LOAD_DATA =>
                    -- Signal ready for input data
                    input_ready <= '1';
                    
                    if input_valid = '1' then
                        input_ready <= '0';
                        compute_en <= '1';
                        current_state <= COMPUTE;
                    end if;
                    
                when COMPUTE =>
                    compute_en <= '0';
                    -- Wait for MAC computation to complete
                    if compute_done = (compute_done'range => '1') then
                        current_state <= FINISH;
                    end if;
                    
                when FINISH =>
                    if region_done = '1' then
                        -- Region processing complete, output results
                        if output_ready = '1' then
                            output_valid <= '1';
                            compute_clear <= '1';
                            pos_advance <= '1';
                            
                            if layer_done = '1' then
                                current_state <= IDLE;
                            else
                                current_state <= LOAD_WEIGHTS;
                            end if;
                        else
                            output_valid <= '0';
                        end if;
                    else
                        -- Continue processing current region
                        pos_advance <= '1';
                        current_state <= LOAD_WEIGHTS;
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