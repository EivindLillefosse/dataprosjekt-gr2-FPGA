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
        clk             : in  std_logic;
        rst             : in  std_logic;
        
        -- Input interface (from previous layer)
        input_valid     : in  std_logic;
        argmax_done     : in  std_logic;
        input_index     : in  integer range 0 to NODES_IN-1;
        
        -- Control signals to calculation module
        calc_clear      : out std_logic;
        calc_compute_en : out std_logic;
        calc_done       : in  std_logic_vector(NODES_OUT-1 downto 0);
        
        -- Output interface
        output_valid    : out std_logic;
        input_ready     : out std_logic  -- Ready to accept new inputs
    );

end fullcon_controller;

architecture RTL of fullcon_controller is

    type state_type is (IDLE, WAIT_WEIGHTS, PROCESSING, WAITING_MAC, DONE);
    signal state         : state_type := IDLE;
    signal all_done          : std_logic := '0';  
    signal all_macs_done : std_logic;


begin

    -- Check if all MACs are done (all bits in calc_done are '1')
    all_macs_done <= '1' when calc_done = (calc_done'range => '1') else '0';

    process(clk,rst)
    begin
        if rst = '1' then
            state            <= IDLE;
            calc_clear       <= '0';
            calc_compute_en  <= '0';
            output_valid     <= '0';
            input_ready      <= '1';

        elsif rising_edge(clk) then
            calc_compute_en  <= '0';
            calc_clear       <= '0';
            output_valid     <= '0';
            input_ready      <= '0';

           case state is
                when IDLE =>
                    output_valid <= '0';

                    if input_valid = '1' then
                        calc_compute_en <= '1';
                        state           <= WAITING_MAC;
                    end if;

                when WAIT_WEIGHTS =>
                    state <= PROCESSING;
                
                when PROCESSING =>
                    if input_valid = '1' then
                        if input_index >= NODES_IN - 1 then
                            all_done <= '1';
                        else
                            all_done <= '0';
                        end if;
                        calc_compute_en <= '1';
                        state           <= WAITING_MAC;
                    end if;                        
                    
                when WAITING_MAC =>
                -- Wait for all MACs to complete their computations
                    if all_macs_done = '1' then
                        -- Guard against off-by-one: treat any index at or beyond the
                        -- final node as the last element so we don't advance past it.
                        if all_done = '1' then
                            output_valid <= '1';
                            all_done <= '0';
                            state <= DONE;
                        else
                            input_ready <= '1';
                            state <= WAIT_WEIGHTS;
                        end if;
                    end if;
                
                when DONE =>

                    if input_valid = '0' or argmax_done = '1' then
                        calc_clear <= '1';
                        state      <= IDLE;
                    end if;
            end case;
        end if;
    end process;end RTL;