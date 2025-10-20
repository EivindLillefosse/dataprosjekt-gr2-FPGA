----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 10.18.2025
-- Design Name: Fully Connected Layer 2
-- Module Name: FC2 - Behavioral
-- Project Name: CNN Accelerator
-- Description: FC layer (64 inputs -> 10 outputs)
--              Retrieves weights, performs MAC for each output, applies ReLU
--              Processes 64 input neurons sequentially from FC1
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity FC2 is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        -- Input interface
        pixel_valid   : in  std_logic;                  -- Input pixel is valid
        pixel_data    : in  WORD;                       -- Input pixel value (8 bits)
        pixel_index   : in  integer range 0 to 63;      -- Position in input (0-63)
        -- Output interface
        output_valid  : out std_logic;                  -- All 10 outputs ready
        output_data   : out WORD_ARRAY(0 to 9)         -- Output neurons after ReLU (8 bits each)
    );
end FC2;

architecture Behavioral of FC2 is

    -- Component declarations
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

    -- Constants
    constant NUM_INPUTS  : integer := 64;
    constant NUM_OUTPUTS : integer := 10;
    constant MAC_WIDTH   : integer := 24;  -- Width of MAC accumulator output

    -- Custom type for 24-bit MAC results
    type MAC_RESULT_ARRAY is array (natural range <>) of std_logic_vector(MAC_WIDTH-1 downto 0);

    -- Signals for dummy weights (for testing)
    signal weight_data : WORD_ARRAY(0 to NUM_OUTPUTS-1) := (others => x"01");  -- Simple weight = 1

    -- Signals for MAC units
    signal mac_pixel_in : std_logic_vector(7 downto 0);
    signal mac_valid    : std_logic;
    signal mac_clear    : std_logic_vector(0 to NUM_OUTPUTS-1);
    signal mac_result   : MAC_RESULT_ARRAY(0 to NUM_OUTPUTS-1);
    signal mac_done     : std_logic_vector(0 to NUM_OUTPUTS-1);

    -- Signals for ReLU
    signal relu_in_valid : std_logic;
    signal relu_in_data  : WORD_ARRAY(0 to NUM_OUTPUTS-1);
    signal relu_out_valid : std_logic;
    signal relu_out_data : WORD_ARRAY(0 to NUM_OUTPUTS-1);

    -- Pixel counter and state
    signal pixel_count : integer range 0 to NUM_INPUTS := 0;
    signal wait_counter : integer range 0 to 15 := 0;
    type state_type is (IDLE, CLEARING, ACCUMULATING, WAITING_MAC, SENDING_RELU, DONE);
    signal state : state_type := IDLE;

begin

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
            weights  => weight_data(i),  -- Use dummy weights
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
        DATA_WIDTH  => 8  -- WORD_ARRAY is always 8-bit words
    )
    port map (
        clk        => clk,
        rst        => rst,
        data_in    => relu_in_data,
        data_valid => relu_in_valid,
        data_out   => relu_out_data,
        valid_out  => relu_out_valid
    );

    -- Main process: control pixel counter and MAC operations
    fc2_proc : process(clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;
            pixel_count <= 0;
            wait_counter <= 0;
            mac_pixel_in <= (others => '0');
            mac_valid <= '0';
            mac_clear <= (others => '0');
            relu_in_valid <= '0';
            relu_in_data <= (others => (others => '0'));
            output_valid <= '0';
            output_data <= (others => (others => '0'));
            
        elsif rising_edge(clk) then
            -- Default: clear one-cycle signals
            mac_valid <= '0';
            mac_clear <= (others => '0');
            relu_in_valid <= '0';

            case state is
                when IDLE =>
                    pixel_count <= 0;
                    wait_counter <= 0;
                    if pixel_valid = '1' then
                        report "FC2: IDLE -> ACCUMULATING, clearing MACs and processing first pixel";
                        -- Clear MACs and immediately start processing the first pixel
                        mac_clear <= (others => '1');
                        mac_pixel_in <= pixel_data;
                        mac_valid <= '1';
                        pixel_count <= 1;
                        state <= ACCUMULATING;
                    end if;
                
                when CLEARING =>
                    -- This state is now unused but kept for compatibility
                    report "FC2: In CLEARING (unused state)";
                    state <= IDLE;
                    
                when ACCUMULATING =>
                    -- Check if we've processed all pixels
                    if pixel_count >= NUM_INPUTS then
                        wait_counter <= 0;
                        state <= WAITING_MAC;
                    elsif pixel_valid = '1' then
                        -- Continue feeding pixels to MACs
                        mac_pixel_in <= pixel_data;
                        mac_valid <= '1';
                        pixel_count <= pixel_count + 1;
                    end if;
                    
                when WAITING_MAC =>
                    -- Wait 10 cycles for MACs to settle (MAC latency + margin)
                    wait_counter <= wait_counter + 1;
                    if wait_counter >= 10 then
                        -- Send results to ReLU
                        relu_in_valid <= '1';
                        for i in 0 to NUM_OUTPUTS-1 loop
                            -- Take middle 8 bits of 24-bit MAC result (bits 15:8)
                            -- This gives us reasonable range without overflow
                            relu_in_data(i) <= mac_result(i)(15 downto 8);
                        end loop;
                        state <= SENDING_RELU;
                    end if;
                    
                when SENDING_RELU =>
                    -- Wait one cycle for ReLU to process
                    if relu_out_valid = '1' then
                        -- Capture output data from ReLU and set output_valid high
                        output_data <= relu_out_data;
                        output_valid <= '1';
                        state <= DONE;
                    end if;
                    
                when DONE =>
                    -- Hold output_valid high until reset or new input
                    output_valid <= '1';
                    if pixel_valid = '1' then
                        output_valid <= '0';
                        state <= IDLE;
                    end if;
            end case;
        end if;
    end process;

end Behavioral;
