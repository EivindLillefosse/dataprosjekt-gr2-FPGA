----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.03.2025
-- Design Name: Fully Connected Weight Memory Controller
-- Module Name: fullcon_memory_controller - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Weight memory management controller for fully connected layers
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fullcon_memory_controller is
    generic (
        NUM_NODES   : integer := 64;
        NUM_INPUTS  : integer := 400;
        LAYER_ID    : integer := 0  -- Select which memory IP to instantiate at elaboration
    );
    port (
        clk         : in  std_logic;
        pixel_index : in  integer range 0 to NUM_INPUTS-1;

        -- Data interface (Ex. 64 bits = 8 nodes * 8 bits per weight)
        weight_data : out WORD_ARRAY(0 to NUM_NODES-1)
    );
end fullcon_memory_controller;

architecture Behavioral of fullcon_memory_controller is

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

    -- Calculate required address width based on number of inputs
    constant WEIGHT_ADDRESSES : natural := NUM_INPUTS; -- total addresses
    constant ADDR_WIDTH : natural := clog2(WEIGHT_ADDRESSES);
    
    -- Calculate data width based on number of nodes
    constant DATA_WIDTH : natural := WORD_SIZE * NUM_NODES;

    COMPONENT layer5_dense_weights
    PORT (
        clka : IN STD_LOGIC;
        ena : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR;
        douta : OUT STD_LOGIC_VECTOR
    );
    END COMPONENT;

    COMPONENT layer6_dense_1_weights
    PORT (
        clka : IN STD_LOGIC;
        ena : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR;
        douta : OUT STD_LOGIC_VECTOR
    );
    END COMPONENT;

    -- Internal signals
    signal weight_addr : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal weight_dout : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

begin

    -- Instantiate weight memory (choose implementation by LAYER_ID)
    gen_mem_0 : if LAYER_ID = 0 generate
        weight_mem_inst : layer5_dense_weights
        PORT MAP (
            clka => clk,
            ena => '1',
            addra => weight_addr,
            douta => weight_dout
        );
    end generate;

    gen_mem_1 : if LAYER_ID = 1 generate
        weight_mem_inst_1 : layer6_dense_1_weights
        PORT MAP (
            clka => clk,
            ena => '1',
            addra => weight_addr,
            douta => weight_dout
        );
    end generate;

    -- Convert BRAM output into WORD_ARRAY elements (WORD_SIZE bits per node)
    -- MSB-first ordering: map weight_data(0) to the top WORD, weight_data(1)
    -- to the next WORD down, etc.
    gen_unpack_weights : for i in 0 to NUM_NODES-1 generate
        weight_data(i) <= weight_dout(DATA_WIDTH - 1 - i*WORD_SIZE downto DATA_WIDTH - (i+1)*WORD_SIZE);
    end generate;

    -- Calculate weight address directly from pixel_index
    weight_addr <= std_logic_vector(to_unsigned(pixel_index, ADDR_WIDTH));

end Behavioral;
