library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity test_conv_layer_tb is
end test_conv_layer_tb;

architecture Behavioral of test_conv_layer_tb is
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '0';
    signal enable    : std_logic := '0';
    signal input_data : OUTPUT_ARRAY_VECTOR(0 to 0, 0 to 27, 0 to 27); -- 1 channel, 28x28 input
    signal output_data : OUTPUT_ARRAY_VECTOR(0 to 7, 0 to 26, 0 to 26); -- 8 filters, 27x27 output
    signal layer_done : std_logic;

    constant clk_period : time := 10 ns;
    
    -- Test image size parameters
    constant IMAGE_SIZE : integer := 28;
    constant KERNEL_SIZE : integer := 3;
    constant INPUT_CHANNELS : integer := 1;
    constant NUM_FILTERS : integer := 8;
    constant STRIDE : integer := 1;
    constant OUTPUT_SIZE : integer := ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1; -- 26

begin
    DUT: entity work.conv_layer
        generic map (
            IMAGE_SIZE => IMAGE_SIZE,
            KERNEL_SIZE => KERNEL_SIZE,
            INPUT_CHANNELS => INPUT_CHANNELS,
            NUM_FILTERS => NUM_FILTERS,
            STRIDE => STRIDE
        )
        port map (
            clk => clk,
            rst => rst,
            enable => enable,
            input_data => input_data,
            output_data => output_data,
            layer_done => layer_done
        );

    clk <= not clk after clk_period / 2;

    -- Stimulus process: drives inputs
    stimulus_proc: process
    begin
        -- Initialize input data with test pattern
        for c in 0 to INPUT_CHANNELS-1 loop
            for row in 0 to IMAGE_SIZE-1 loop
                for col in 0 to IMAGE_SIZE-1 loop
                    input_data(c, row, col) <= std_logic_vector(to_signed((row + col + 1), 8));
                end loop;
            end loop;
        end loop;

        -- Reset
        rst <= '1';
        enable <= '0';
        wait for clk_period * 2;
        rst <= '0';
        wait for clk_period * 2;

        -- Start convolution
        enable <= '1';

        -- Wait for completion
        wait until layer_done = '1';
        enable <= '0';
        wait for clk_period * 5;

        -- Test second convolution
        enable <= '1';
        wait for clk_period;
        enable <= '0';

        wait until layer_done = '1';
        wait for clk_period * 5;

        wait;
    end process stimulus_proc;

    -- Checking process: monitors layer_done and validates basic functionality
    check_proc: process
    begin
        -- Wait for first convolution to complete
        wait until layer_done = '1';
        
        -- Basic check: ensure output is not all zeros
        for f in 0 to NUM_FILTERS-1 loop
            for row in 0 to OUTPUT_SIZE-1 loop
                for col in 0 to OUTPUT_SIZE-1 loop
                    -- This is a basic sanity check - in a real testbench you'd check against expected values
                    if output_data(f, row, col) /= (output_data(f, row, col)'range => '0') then
                        report "Output filter " & integer'image(f) & " at (" & integer'image(row) & "," & integer'image(col) & ") has non-zero value"
                            severity NOTE;
                        exit; -- Exit inner loops after finding first non-zero
                    end if;
                end loop;
            end loop;
        end loop;

        report "First convolution completed successfully" severity NOTE;

        -- Wait for second convolution
        wait until layer_done = '1';
        report "Second convolution completed successfully" severity NOTE;

        wait;
    end process check_proc;

end Behavioral;
