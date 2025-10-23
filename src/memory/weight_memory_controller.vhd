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

        -- Control interface
        load_req    : in  std_logic;
        kernel_row  : in  integer range 0 to KERNEL_SIZE-1;
        kernel_col  : in  integer range 0 to KERNEL_SIZE-1;

        -- Data interface (64 bits = 8 filters * 8 bits per weight)
        weight_data : out WORD_ARRAY(0 to NUM_FILTERS-1)
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
    signal weight_dout : std_logic_vector(63 downto 0) := (others => '0');  -- Raw 64-bit output from BRAM IP

begin

    -- Instantiate weight memory
    weight_mem_inst : layer0_conv2d_weights
    PORT MAP (
        clka => clk,
        ena => load_req,
        addra => weight_addr,
        douta => weight_dout
    );

    -- Convert 64-bit BRAM output into WORD_ARRAY elements (8 bits per filter)
    -- Each byte in the 64-bit output corresponds to one filter's weight
    gen_unpack_weights : for i in 0 to NUM_FILTERS-1 generate
        weight_data(i) <= weight_dout((i+1)*8 - 1 downto i*8);
    end generate;

    -- Calculate weight address based on kernel position
    weight_addr <= std_logic_vector(to_unsigned(kernel_row * KERNEL_SIZE + kernel_col, 4));


end Behavioral;