----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 11.05.2025
-- Design Name: FC Layer Buffer Testbench
-- Module Name: fc_layer_buffer_tb
-- Project Name: CNN Accelerator
-- Description: Testbench for fc_layer_buffer
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fc_layer_buffer_tb is
end fc_layer_buffer_tb;

architecture tb of fc_layer_buffer_tb is

    constant NUM_NEURONS : integer := 64;
    constant CLK_PERIOD : time := 10 ns;

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal input_valid   : std_logic := '0';
    signal input_data    : WORD_ARRAY(0 to NUM_NEURONS-1);
    signal input_ready   : std_logic;
    signal output_valid  : std_logic;
    signal output_data   : WORD_ARRAY(0 to NUM_NEURONS-1);
    signal output_ready  : std_logic := '0';

begin

    -- Instantiate the buffer
    DUT : entity work.fc_layer_buffer
        generic map (
            DATA_WIDTH => 8,
            NUM_NEURONS => NUM_NEURONS
        )
        port map (
            clk => clk,
            rst => rst,
            input_valid => input_valid,
            input_data => input_data,
            input_ready => input_ready,
            output_valid => output_valid,
            output_data => output_data,
            output_ready => output_ready
        );

    -- Clock generation
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Test stimulus
    process
    begin
        -- Reset
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        report "Test 1: Buffer initially empty" severity note;
        assert input_ready = '1' report "Buffer should be ready initially" severity error;
        assert output_valid = '0' report "Output should be invalid initially" severity error;
        wait for CLK_PERIOD;

        report "Test 2: Write data to buffer" severity note;
        -- Create test data
        for i in 0 to NUM_NEURONS-1 loop
            input_data(i) <= std_logic_vector(to_unsigned(i, 8));
        end loop;
        input_valid <= '1';
        wait for CLK_PERIOD;
        input_valid <= '0';
        wait for CLK_PERIOD;

        report "Test 3: Buffer is full with data" severity note;
        assert output_valid = '1' report "Output should be valid after write" severity error;
        assert input_ready = '0' report "Input should not be ready when buffer is full" severity error;

        -- Verify stored data
        for i in 0 to NUM_NEURONS-1 loop
            assert output_data(i) = std_logic_vector(to_unsigned(i, 8)) 
                report "Output data mismatch at index " & integer'image(i) severity error;
        end loop;
        wait for CLK_PERIOD;

        report "Test 4: FC2 reads from buffer" severity note;
        output_ready <= '1';
        wait for CLK_PERIOD;

        report "Test 5: Buffer is draining" severity note;
        assert output_valid = '1' report "Output should still be valid during drain" severity error;
        wait for CLK_PERIOD;

        report "Test 6: FC2 stops reading" severity note;
        output_ready <= '0';
        wait for CLK_PERIOD;

        report "Test 7: Buffer returns to empty" severity note;
        assert input_ready = '1' report "Buffer should be ready again" severity error;
        assert output_valid = '0' report "Output should be invalid when empty" severity error;
        wait for CLK_PERIOD;

        report "Test 8: Multiple writes and reads" severity note;
        -- First write
        for i in 0 to NUM_NEURONS-1 loop
            input_data(i) <= std_logic_vector(to_unsigned(i + 10, 8));
        end loop;
        input_valid <= '1';
        wait for CLK_PERIOD;
        input_valid <= '0';
        wait for CLK_PERIOD;

        -- Verify data
        for i in 0 to NUM_NEURONS-1 loop
            assert output_data(i) = std_logic_vector(to_unsigned(i + 10, 8)) 
                report "Second write: data mismatch at index " & integer'image(i) severity error;
        end loop;

        -- Immediate read
        output_ready <= '1';
        wait for CLK_PERIOD;
        output_ready <= '0';
        wait for CLK_PERIOD;

        assert input_ready = '1' report "Buffer should be ready after draining" severity error;

        report "All tests passed!" severity note;
        wait;
    end process;

end tb;
