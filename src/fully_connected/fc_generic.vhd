----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 10.18.2025
-- Design Name: Generic Fully Connected Layer
-- Module Name: fc_generic - Behavioral
-- Project Name: CNN Accelerator
-- Description: Modular, generic fully connected layer
--              Retrieves weights from memory and performs MAC operations
--              Works for any input/output size by adjusting generics
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fc_generic is
    generic (
        NUM_INPUTS  : integer := 400;  -- Number of input neurons
        NUM_OUTPUTS : integer := 64;   -- Number of output neurons
        ADDR_WIDTH  : integer := 15    -- Address width for weight memory
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        -- Input interface
        pixel_valid   : in  std_logic;                           -- Input pixel is valid
        pixel_data    : in  WORD;                                -- Input pixel value (8 bits)
        pixel_index   : in  integer range 0 to NUM_INPUTS-1;     -- Position in input (0 to NUM_INPUTS-1)
        -- Weight memory interface
        weight_data   : out WORD_ARRAY(0 to NUM_OUTPUTS-1);     -- Retrieved weights for this pixel
        weight_valid  : out std_logic;                           -- Weights are valid
        weight_addr   : out std_logic_vector(ADDR_WIDTH-1 downto 0);  -- Address to weight memory
        weight_en     : out std_logic                            -- Enable weight memory read
    );
end fc_generic;

architecture Behavioral of fc_generic is

    -- Component instantiation for weight memory controller
    COMPONENT weight_memory_controller
    generic (
        NUM_FILTERS : integer;
        KERNEL_SIZE : integer;
        ADDR_WIDTH  : integer
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        load_req    : in  std_logic;
        kernel_row  : in  integer;
        kernel_col  : in  integer;
        weight_data : out WORD_ARRAY(0 to NUM_FILTERS-1);
        data_valid  : out std_logic
    );
    END COMPONENT;

    -- Internal signals for weight memory controller
    signal mem_load_req     : std_logic := '0';
    signal mem_kernel_row   : integer := 0;
    signal mem_kernel_col   : integer := 0;
    signal mem_weight_data  : WORD_ARRAY(0 to NUM_OUTPUTS-1);
    signal mem_data_valid   : std_logic;
    
    -- Calculate KERNEL_SIZE for memory controller (dimension of grid)
    -- We map NUM_INPUTS to a square or rectangular grid
    constant KERNEL_SIZE : integer := integer(real(NUM_INPUTS) ** 0.5);  -- Approximate sqrt

begin

    -- Instantiate weight memory controller
    weight_mem_controller_inst : weight_memory_controller
    generic map (
        NUM_FILTERS => NUM_OUTPUTS,
        KERNEL_SIZE => KERNEL_SIZE,
        ADDR_WIDTH  => ADDR_WIDTH
    )
    port map (
        clk         => clk,
        rst         => rst,
        load_req    => mem_load_req,
        kernel_row  => mem_kernel_row,
        kernel_col  => mem_kernel_col,
        weight_data => mem_weight_data,
        data_valid  => mem_data_valid
    );

    -- Function to retrieve weights from memory
    -- Maps pixel_index to kernel_row and kernel_col coordinates
    weight_retrieval_process : process(clk, rst)
    begin
        if rst = '1' then
            mem_load_req <= '0';
            weight_valid <= '0';
            weight_data <= (others => (others => '0'));
            weight_addr <= (others => '0');
            weight_en <= '0';
            
        elsif rising_edge(clk) then
            -- Check if we have a valid input pixel
            if pixel_valid = '1' then
                -- Convert pixel_index to kernel_row and kernel_col
                -- Map to KERNEL_SIZE x KERNEL_SIZE grid
                mem_kernel_row <= pixel_index / KERNEL_SIZE;
                mem_kernel_col <= pixel_index mod KERNEL_SIZE;
                mem_load_req <= '1';
            else
                mem_load_req <= '0';
            end if;
            
            -- Pass through weight memory controller outputs
            weight_data <= mem_weight_data;
            weight_valid <= mem_data_valid;
        end if;
    end process;

end Behavioral;
