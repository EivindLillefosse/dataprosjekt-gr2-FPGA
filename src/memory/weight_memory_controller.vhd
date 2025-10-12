----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 05.10.2025
-- Design Name: Weight Memory Controller
-- Module Name: weight_memory_controller - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Modular weight memory management controller
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity weight_memory_controller is
    generic (
        NUM_FILTERS : integer := 8;
        KERNEL_SIZE : integer := 3;
        ADDR_WIDTH  : integer := 7
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        -- Control interface
        load_req    : in  std_logic;
        kernel_row  : in  integer range 0 to KERNEL_SIZE-1;
        kernel_col  : in  integer range 0 to KERNEL_SIZE-1;
        -- Data interface (64 bits = 8 filters * 8 bits per weight)
        weight_data : out WORD_ARRAY(0 to NUM_FILTERS-1);
        data_valid  : out std_logic;
        load_done   : out std_logic
    );
end weight_memory_controller;

architecture Behavioral of weight_memory_controller is

    COMPONENT layer0_conv2d_weights
    PORT (
        clka : IN STD_LOGIC;
        ena : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR(3 DOWNTO 0);  -- Address width reduced (9 positions instead of 72)
        douta : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)  -- 64-bit output (8 weights)
    );
    END COMPONENT;

    -- Internal signals
    signal weight_addr : std_logic_vector(3 downto 0) := (others => '0');  -- Only need 4 bits for 9 addresses
    signal weight_en   : std_logic := '0';
    signal wait_cycles : integer range 0 to 3 := 0;
    signal weight_dout : std_logic_vector(63 downto 0) := (others => '0');  -- Raw 64-bit output from BRAM IP
    
    type state_type is (IDLE, LOAD_REQUEST, WAIT_DATA, DATA_READY);
    signal current_state : state_type := IDLE;

begin

    -- Instantiate weight memory
    weight_mem_inst : layer0_conv2d_weights
    PORT MAP (
        clka => clk,
        ena => weight_en,
        addra => weight_addr,
        douta => weight_dout
    );

    -- Convert 64-bit BRAM output into WORD_ARRAY elements (8 bits per filter)
    -- Each byte in the 64-bit output corresponds to one filter's weight
    gen_unpack_weights : for i in 0 to NUM_FILTERS-1 generate
        weight_data(i) <= weight_dout((i+1)*8 - 1 downto i*8);
    end generate;

    -- Memory controller process
    memory_ctrl_proc: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            weight_en <= '0';
            data_valid <= '0';
            load_done <= '0';
            wait_cycles <= 0;
            weight_addr <= (others => '0');
            
        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    data_valid <= '0';
                    load_done <= '0';
                    weight_en <= '0';
                    
                    if load_req = '1' then
                        -- Calculate memory address (kernel position only, all filters loaded together)
                        -- Address = kernel_row * KERNEL_SIZE + kernel_col
                        weight_addr <= std_logic_vector(to_unsigned(
                            kernel_row * KERNEL_SIZE + kernel_col, 4));
                        weight_en <= '1';
                        wait_cycles <= 0;
                        current_state <= LOAD_REQUEST;
                    end if;
                    
                when LOAD_REQUEST =>
                    -- Wait for BRAM read latency
                    wait_cycles <= wait_cycles + 1;
                    if wait_cycles >= 2 then
                        weight_en <= '0';
                        current_state <= WAIT_DATA;
                    end if;
                    
                when WAIT_DATA =>
                    -- Data should be available now
                    current_state <= DATA_READY;
                    
                when DATA_READY =>
                    data_valid <= '1';
                    load_done <= '1';
                    current_state <= IDLE;
                    
                when others =>
                    current_state <= IDLE;
            end case;
        end if;
    end process;

end Behavioral;