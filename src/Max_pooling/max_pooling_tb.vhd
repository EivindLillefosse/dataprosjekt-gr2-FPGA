library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity max_pooling_tb is
end max_pooling_tb;

architecture sim of max_pooling_tb is
    constant CONV_SIZE   : integer := 8;  -- 8x8 matrix
    constant POOL_SIZE   : integer := 2;
    constant NUM_FILTERS : integer := 2;  -- Testing with 2 filters
    constant OUT_SIZE    : integer := CONV_SIZE / POOL_SIZE;
    subtype pixel_t is std_logic_vector(7 downto 0);

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '0';
    signal enable: std_logic := '0';
    signal done  : std_logic;
    signal input_data  : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1, 0 to CONV_SIZE-1, 0 to CONV_SIZE-1);
    signal output_data : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1, 0 to OUT_SIZE-1, 0 to OUT_SIZE-1);

begin
    -- Clock generation
    clk_proc: process
    begin
        while true loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
    end process;

    -- DUT instantiation
    dut: entity work.max_pooling
        generic map (
            CONV_SIZE   => CONV_SIZE,
            POOL_SIZE   => POOL_SIZE,
            NUM_FILTERS => NUM_FILTERS
        )
        port map (
            clk         => clk,
            rst         => rst,
            enable      => enable,
            input_data  => input_data,
            output_data => output_data,
            done        => done
        );

    -- Stimulus process
    stim_proc: process
    begin
        -- Reset
        rst <= '1';
        enable <= '0';
        wait for 20 ns;
        rst <= '0';
        wait for 10 ns;

        -- Initialize all inputs to zero first
        for f in 0 to NUM_FILTERS-1 loop
            for i in 0 to CONV_SIZE-1 loop
                for j in 0 to CONV_SIZE-1 loop
                    input_data(f, i, j) <= (others => '0');
                end loop;
            end loop;
        end loop;

        -- Test case 1: First filter - place test pattern in first 2x2 block
        input_data(0, 0, 0) <= std_logic_vector(to_unsigned(1, 8));
        input_data(0, 0, 1) <= std_logic_vector(to_unsigned(9, 8));
        input_data(0, 1, 0) <= std_logic_vector(to_unsigned(3, 8));
        input_data(0, 1, 1) <= std_logic_vector(to_unsigned(4, 8));
        
        -- Test case 2: Second filter - place test pattern in first 2x2 block
        input_data(0, 2, 3) <= std_logic_vector(to_unsigned(5, 8));
        input_data(0, 2, 4) <= std_logic_vector(to_unsigned(6, 8));
        input_data(0, 3, 3) <= std_logic_vector(to_unsigned(3, 8));
        input_data(0, 3, 4) <= std_logic_vector(to_unsigned(7, 8));

        -- Start pooling
        enable <= '1';
        wait until done = '1';
        enable <= '0';
        wait for 10 ns;

        -- Print the results
        report "=== Test Results ===";
        report "Filter 0 first block (should be 4): " & 
               integer'image(to_integer(unsigned(output_data(0, 0, 0))));
        report "Filter 1 first block (should be 8): " & 
               integer'image(to_integer(unsigned(output_data(1, 0, 0))));
        
        -- Also print some other outputs to verify they're zero
        report "Filter 0 next block: " & 
               integer'image(to_integer(unsigned(output_data(0, 0, 1))));
        report "Filter 1 next block: " & 
               integer'image(to_integer(unsigned(output_data(1, 0, 1))));
    
        wait;
    end process;

end architecture sim;
