----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Bias Memory Controller
-- Module Name: bias_memory_controller - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular bias memory management controller
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity bias_memory_controller is
    generic (
        NUM_FILTERS : integer := 8;
        ADDR_WIDTH  : integer := 3
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        -- Control interface
        load_req    : in  std_logic;
        filter_idx  : in  integer range 0 to NUM_FILTERS-1;
        -- Data interface
        bias_data   : out std_logic_vector(7 downto 0);
        data_valid  : out std_logic
    );
end bias_memory_controller;

architecture Behavioral of bias_memory_controller is

    COMPONENT layer0_conv2d_biases
    PORT (
        clka : IN STD_LOGIC;
        ena : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) 
    );
    END COMPONENT;

    -- Internal signals
    signal bias_addr : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal bias_en   : std_logic := '0';
    signal wait_cycles : integer range 0 to 3 := 0;
    
    type state_type is (IDLE, LOAD_REQUEST, WAIT_DATA, DATA_READY);
    signal current_state : state_type := IDLE;

begin

    -- Instantiate bias memory
    bias_mem_inst : layer0_conv2d_biases
    PORT MAP (
        clka => clk,
        ena => bias_en,
        addra => bias_addr,
        douta => bias_data
    );

    -- Memory controller process
    memory_ctrl_proc: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            bias_en <= '0';
            data_valid <= '0';
            wait_cycles <= 0;
            bias_addr <= (others => '0');
            
        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    data_valid <= '0';
                    bias_en <= '0';
                    
                    if load_req = '1' then
                        -- Calculate memory address (simple filter index)
                        bias_addr <= std_logic_vector(to_unsigned(filter_idx, ADDR_WIDTH));
                        bias_en <= '1';
                        wait_cycles <= 0;
                        current_state <= LOAD_REQUEST;
                    end if;
                    
                when LOAD_REQUEST =>
                    -- Wait for BRAM read latency
                    wait_cycles <= wait_cycles + 1;
                    if wait_cycles >= 2 then
                        bias_en <= '0';
                        current_state <= WAIT_DATA;
                    end if;
                    
                when WAIT_DATA =>
                    -- Data should be available now
                    current_state <= DATA_READY;
                    
                when DATA_READY =>
                    data_valid <= '1';
                    current_state <= IDLE;
                    
                when others =>
                    current_state <= IDLE;
            end case;
        end if;
    end process;

end Behavioral;