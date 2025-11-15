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
        NUM_FILTERS        : integer := 8;
        NUM_INPUT_CHANNELS : integer := 1;
        KERNEL_SIZE        : integer := 3;
        LAYER_ID           : integer := 0  -- Select which memory IP to instantiate at elaboration
    );
    port (
        clk         : in  std_logic;
        kernel_row  : in  integer range 0 to KERNEL_SIZE-1;
        kernel_col  : in  integer range 0 to KERNEL_SIZE-1;
        channel     : in  integer range 0 to NUM_INPUT_CHANNELS-1;

        -- Data interface (Ex. 64 bits = 8 filters * 8 bits per weight)
        weight_data : out WORD_ARRAY(0 to NUM_FILTERS-1)
    );
end weight_memory_controller;

architecture Behavioral of weight_memory_controller is

    -- helper: compute ceiling(log2(n)) for address width
    function clog2(n : natural) return natural is
        variable v : natural := n;
        variable bits : natural := 0;
    begin
        if v <= 1 then
            return 1;
        end if;
        v := v - 1;
        while v > 0 loop
            v := v / 2;
            bits := bits + 1;
        end loop;
        return bits;
    end function;

    -- Calculate required address width based on kernel positions and input channels
    -- Each kernel position has NUM_INPUT_CHANNELS addresses (one per channel)
    constant WEIGHT_ADDRESSES : natural := KERNEL_SIZE * KERNEL_SIZE * NUM_INPUT_CHANNELS; -- total addresses
    constant ADDR_WIDTH : natural := clog2(WEIGHT_ADDRESSES);

    COMPONENT layer0_conv2d_weights
    PORT (
        clka : IN STD_LOGIC;
        ena : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR(ADDR_WIDTH-1 DOWNTO 0);  -- address width derived from generics
        douta : OUT STD_LOGIC_VECTOR(WORD_SIZE*NUM_FILTERS-1 DOWNTO 0)
    );
    END COMPONENT;

    COMPONENT layer2_conv2d_1_weights
    PORT (
        clka  : IN STD_LOGIC;
        ena   : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR(ADDR_WIDTH-1 DOWNTO 0);
        douta : OUT STD_LOGIC_VECTOR(WORD_SIZE*NUM_FILTERS-1 DOWNTO 0)
    );
    END COMPONENT;

    -- Internal signals
    signal weight_addr : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal weight_dout : std_logic_vector(WORD_SIZE*NUM_FILTERS-1 downto 0) := (others => '0');  -- Raw output from BRAM IP

begin

    -- Instantiate weight memory (choose implementation by LAYER_ID)
    gen_mem_0 : if LAYER_ID = 0 generate
        weight_mem_inst : layer0_conv2d_weights
        PORT MAP (
            clka => clk,
            ena => '1',
            addra => weight_addr,
            douta => weight_dout
        );
    end generate;

    gen_mem_1 : if LAYER_ID = 1 generate
        weight_mem_inst_1 : layer2_conv2d_1_weights
        PORT MAP (
            clka => clk,
            ena => '1',
            addra => weight_addr,
            douta => weight_dout
        );
    end generate;

    -- Convert BRAM output into WORD_ARRAY elements (WORD_SIZE bits per filter)
    -- Each WORD in the output corresponds to one filter's weight.
    -- COE/BRAM uses MSB-first packing for our export: filter 0 is at the TOP WORD
    -- (bits WORD_SIZE*NUM_FILTERS-1 downto WORD_SIZE*(NUM_FILTERS-1)), and
    -- filter NUM_FILTERS-1 is at the BOTTOM (bits WORD_SIZE-1 downto 0).
    -- Map accordingly so weight_data(0) receives the TOP WORD.
    gen_unpack_weights : for i in 0 to NUM_FILTERS-1 generate
        -- MSB-first ordering: top-most WORD corresponds to filter 0
        weight_data(i) <= weight_dout(WORD_SIZE*NUM_FILTERS-1 - i*WORD_SIZE downto WORD_SIZE*NUM_FILTERS - (i+1)*WORD_SIZE);
    end generate;

    -- Calculate weight address for the kernel position and channel
    -- addr = ((kernel_row * KERNEL_SIZE) + kernel_col) * NUM_INPUT_CHANNELS + channel
    weight_addr <= std_logic_vector(
        to_unsigned(
            (kernel_row * KERNEL_SIZE + kernel_col) * NUM_INPUT_CHANNELS + channel,
            ADDR_WIDTH
        )
    );


end Behavioral;