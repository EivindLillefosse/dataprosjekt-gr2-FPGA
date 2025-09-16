library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity window_generator_tb is
end window_generator_tb;

architecture Behavioral of window_generator_tb is

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal enable : std_logic := '0';
    signal input_data : PIXEL := (others => '0');
    signal output_data : IMAGE_VECTOR;
    signal done : std_logic;

    constant clk_period : time := 10 ns;

    -- Test data
    type pixel_array is array (0 to 17) of integer;
    constant test_pixels : pixel_array := (10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180);
    signal pixel_index : integer := 0;
    signal expected_output : IMAGE_VECTOR := (others => (others => (others => '0')));
    signal expected_done : std_logic := '0';
    signal test_passed : boolean := true;
begin


    uut: entity work.window_gen
        port map (
            clk => clk,
            rst => rst,
            enable => enable,
            input_data => input_data,
            output_data => output_data,
            done => done
        );

    clk <= not clk after clk_period / 2;

    process
    begin
        -- Reset
        rst <= '1';
        enable <= '0';
        wait for clk_period * 2;
        rst <= '0';
        wait for clk_period * 2;

        -- Start feeding pixels
        enable <= '1';
        for i in 0 to 17 loop
            input_data <= std_logic_vector(to_unsigned(test_pixels(i), 8));
            pixel_index <= i;
            wait for clk_period;

            -- Check output when done is high
            if done = '1' then
                expected_done <= '1';
                -- Construct expected output window
                for r in 0 to KERNEL_SIZE-1 loop
                    for c in 0 to KERNEL_SIZE-1 loop
                        expected_output(r, c) <= std_logic_vector(to_unsigned(test_pixels(i - (KERNEL_SIZE - 1 - r) * KERNEL_SIZE - (KERNEL_SIZE - 1 - c)), 8));
                    end loop;
                end loop;

                -- Compare output_data with expected_output
                if output_data /= expected_output then
                    test_passed <= false;
                    report "Test failed at pixel index " & integer'image(i) severity error;
                end if;
            else
                expected_done <= '0';
            end if;
        end loop;

        enable <= '0';
        wait for clk_period * 5;

        if test_passed then
            report "All tests passed!" severity note;
        else
            report "Some tests failed." severity error;
        end if;

        wait;
    end process;

end Behavioral;