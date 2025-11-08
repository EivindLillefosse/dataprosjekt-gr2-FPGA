----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 10.18.2025
-- Design Name: Fully Connected
-- Module Name: FullyConnected - RTL
-- Project Name: CNN Accelerator
-- Description: Controller
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fullcon_controller is
    generic (
        NODES_IN  : integer := 400;
        NODES_OUT : integer := 64;
        LAYER_ID  : integer := 0
    );

    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        
        -- Input interface (from previous layer)
        input_valid : in  std_logic;
        input_index : in  integer range 0 to NODES_IN-1;
        
        -- Control signals to calculation module
        calc_clear     : out std_logic;
        calc_compute_en: out std_logic;
        
        -- Output interface
        output_valid : out std_logic;
        input_ready  : out std_logic  -- Ready to accept new inputs
    );

end fullcon_controller;

architecture RTL of fullcon_controller is

    type state_type is (IDLE, PROCESSING, WAITING_MAC, DONE);
    signal state : state_type := IDLE;
    
    signal input_count : integer range 0 to NODES_IN := 0;
    signal wait_counter : integer range 0 to 10 := 0;

begin
    process(clk,rst)
    begin
        if rst = '1' then
            state <= IDLE;
            input_count <= 0;
            calc_clear <= '0';
            calc_compute_en <= '0';
            output_valid <= '0';
            input_ready <= '1';
            wait_counter <= 0;

        elsif rising_edge(clk) then
            calc_compute_en <= '0';
            calc_clear <= '0';

           case state is
                when IDLE =>
                    input_ready <= '1';
                    output_valid <= '0';
                    
                    if input_valid = '1' and input_index = 0 then
                        calc_clear <= '1';
                        calc_compute_en <= '1';
                        state <= PROCESSING;
                    end if;
                
                when PROCESSING =>
                    input_ready <= '1';
                    
                    if input_valid = '1' then
                        calc_compute_en <= '1';
                        
                        if input_index = NODES_IN - 1 then
                            wait_counter <= 0;
                            state <= WAITING_MAC;
                            input_ready <= '0';
                        end if;
                    end if;                        
                
                when WAITING_MAC =>
                    input_ready <= '0';
                    wait_counter <= wait_counter + 1;
                    
                    if wait_counter >= 3 then
                        output_valid <= '1';
                        -- Stay in WAITING_MAC with output_valid high
                        -- until new frame starts
                    end if;
                    
                    -- Return to IDLE when new frame starts
                    if input_valid = '1' and input_index = 0 then
                        output_valid <= '0';
                        state <= IDLE;
                    end if;
                
                when others =>
                    state <= IDLE;
                    
            end case;
        end if;
    end process;end RTL;