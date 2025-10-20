----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 10.18.2025
-- Design Name: Fully Connected Layer 1
-- Module Name: FC1 - Behavioral
-- Project Name: CNN Accelerator
-- Description: FC layer (400 inputs -> 64 outputs)
--              Retrieves weights, performs MAC for each output, applies ReLU
--              Processes 400 input pixels sequentially
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity FC1 is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        -- Input interface
        pixel_valid   : in  std_logic;                  -- Input pixel is valid
        pixel_data    : in  WORD;                       -- Input pixel value (8 bits)
        pixel_index   : in  integer range 0 to 399;     -- Position in input (0-399)
        -- Output interface
        output_valid  : out std_logic;                  -- All 64 outputs ready
        output_data   : out WORD_ARRAY(0 to 63)        -- Output neurons after ReLU (8 bits each)
    );
end FC1;

architecture Behavioral of FC1 is

    -- Component declarations
    COMPONENT fc_generic
    generic (
        NUM_INPUTS  : integer;
        NUM_OUTPUTS : integer;
        ADDR_WIDTH  : integer
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        pixel_valid   : in  std_logic;
        pixel_data    : in  WORD;
        pixel_index   : in  integer range 0 to NUM_INPUTS-1;
        weight_data   : out WORD_ARRAY(0 to NUM_OUTPUTS-1);
        weight_valid  : out std_logic;
        weight_addr   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        weight_en     : out std_logic
    );
    END COMPONENT;

    COMPONENT MAC
    generic (
        width_a : integer;
        width_b : integer;
        width_p : integer
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        pixel_in : in  std_logic_vector(width_a-1 downto 0);
        weights  : in  std_logic_vector(width_b-1 downto 0);
        valid    : in  std_logic;
        clear    : in  std_logic;
        result   : out std_logic_vector(width_p-1 downto 0);
        done     : out std_logic
    );
    END COMPONENT;

    COMPONENT relu_layer
    generic (
        NUM_FILTERS : integer;
        DATA_WIDTH  : integer
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        data_in    : in  WORD_ARRAY(0 to NUM_FILTERS-1);
        data_valid : in  std_logic;
        data_out   : out WORD_ARRAY(0 to NUM_FILTERS-1);
        valid_out  : out std_logic
    );
    END COMPONENT;

    COMPONENT layer5_dense_biases
    PORT (
        clka  : IN STD_LOGIC;
        ena   : IN STD_LOGIC;
        addra : IN STD_LOGIC_VECTOR(5 DOWNTO 0);
        douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
    END COMPONENT;

    -- Constants
    constant NUM_INPUTS  : integer := 400;
    constant NUM_OUTPUTS : integer := 64;
    constant ADDR_WIDTH  : integer := 15;
    constant MAC_WIDTH   : integer := 24;  -- Width of MAC accumulator output

    -- Signals from weight memory
    signal weight_mem_valid : std_logic;
    signal weight_mem_data  : WORD_ARRAY(0 to NUM_OUTPUTS-1);
    signal weight_mem_addr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal weight_mem_en    : std_logic;

    -- Signals for MAC units
    signal mac_pixel_in : std_logic_vector(7 downto 0);
    signal mac_valid    : std_logic;
    signal mac_clear    : std_logic_vector(0 to NUM_OUTPUTS-1);
    signal mac_result   : WORD_ARRAY_16(0 to NUM_OUTPUTS-1);
    signal mac_done     : std_logic_vector(0 to NUM_OUTPUTS-1);

    -- Signals for bias memory
    signal bias_mem_en   : std_logic := '0';
    signal bias_mem_addr : std_logic_vector(5 downto 0) := (others => '0');
    signal bias_mem_data : std_logic_vector(7 downto 0) := (others => '0');

    -- Signals for ReLU
    signal relu_in_valid : std_logic;
    signal relu_in_data  : WORD_ARRAY(0 to NUM_OUTPUTS-1);
    signal relu_out_valid : std_logic;

    -- Pixel counter
    signal pixel_count : integer range 0 to NUM_INPUTS := 0;
    
    -- Output counter (for bias retrieval)
    signal output_count : integer range 0 to NUM_OUTPUTS := 0;

begin

    -- Instantiate weight memory retrieval module
    weight_memory_inst : fc_generic
    generic map (
        NUM_INPUTS  => NUM_INPUTS,
        NUM_OUTPUTS => NUM_OUTPUTS,
        ADDR_WIDTH  => ADDR_WIDTH
    )
    port map (
        clk         => clk,
        rst         => rst,
        pixel_valid => pixel_valid,
        pixel_data  => pixel_data,
        pixel_index => pixel_index,
        weight_data => weight_mem_data,
        weight_valid => weight_mem_valid
    );

    -- Generate MAC units for each output neuron
    mac_gen: for i in 0 to NUM_OUTPUTS-1 generate
        mac_inst : MAC
        generic map (
            width_a => 8,
            width_b => 8,
            width_p => MAC_WIDTH
        )
        port map (
            clk      => clk,
            rst      => rst,
            pixel_in => mac_pixel_in,
            weights  => weight_mem_data(i),
            valid    => mac_valid,
            clear    => mac_clear(i),
            result   => mac_result(i),
            done     => mac_done(i)
        );
    end generate mac_gen;

    -- Instantiate ReLU layer
    relu_inst : relu_layer
    generic map (
        NUM_FILTERS => NUM_OUTPUTS,
        DATA_WIDTH  => MAC_WIDTH
    )
    port map (
        clk        => clk,
        rst        => rst,
        data_in    => relu_in_data,
        data_valid => relu_in_valid,
        data_out   => output_data,
        valid_out  => output_valid
    );

    -- Instantiate bias memory
    bias_mem_inst : layer5_dense_biases
    PORT MAP (
        clka  => clk,
        ena   => bias_mem_en,
        addra => bias_mem_addr,
        douta => bias_mem_data
    );

    -- Main process: control pixel counter and MAC operations
    fc1_proc : process(clk, rst)
    begin
        if rst = '1' then
            pixel_count <= 0;
            output_count <= 0;
            mac_pixel_in <= (others => '0');
            mac_valid <= '0';
            mac_clear <= (others => '0');
            relu_in_valid <= '0';
            bias_mem_en <= '0';
            bias_mem_addr <= (others => '0');
            
        elsif rising_edge(clk) then
            mac_valid <= '0';
            mac_clear <= (others => '0');
            relu_in_valid <= '0';
            bias_mem_en <= '0';

            -- Check if all pixels have been processed and MAC done
            if pixel_count >= NUM_INPUTS then
                -- All pixels processed - check if MAC is complete
                if mac_done = (0 to NUM_OUTPUTS-1 => '1') then
                    -- All MACs done - retrieve biases and add to MAC results
                    if output_count < NUM_OUTPUTS then
                        bias_mem_en <= '1';
                        bias_mem_addr <= std_logic_vector(to_unsigned(output_count, 6));
                        output_count <= output_count + 1;
                    else
                        -- All biases retrieved, pass to ReLU
                        relu_in_valid <= '1';
                        for i in 0 to NUM_OUTPUTS-1 loop
                            -- Add bias to MAC result and take upper 8 bits
                            relu_in_data(i) <= std_logic_vector(
                                unsigned(mac_result(i)(15 downto 8)) + 
                                unsigned(bias_mem_data)
                            );
                        end loop;
                        pixel_count <= 0;  -- Reset for next batch
                        output_count <= 0;
                    end if;
                end if;
            elsif pixel_valid = '1' and weight_mem_valid = '1' then
                -- Valid pixel and weight data available
                mac_pixel_in <= pixel_data;
                mac_valid <= '1';
                pixel_count <= pixel_count + 1;
                
                -- Clear MAC on first pixel
                if pixel_count = 0 then
                    mac_clear <= (others => '1');
                end if;
            end if;
        end if;
    end process;

end Behavioral;
   