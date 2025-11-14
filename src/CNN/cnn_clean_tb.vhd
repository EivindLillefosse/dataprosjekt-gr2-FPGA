----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse, Martin Brekke Nilsen, Nikolai Sandvik Nore
--
-- Create Date: 14.11.2025
-- Design Name: CNN Accelerator
-- Module Name: cnn_clean_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Testbench for clean top-level `cnn_top` using exported test images
--              Mirrors the behavior of `cnn_real_data_tb.vhd` but instantiates
--              the debug-free `cnn_top` entity.
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;
use work.test_image_pkg.all;  -- Real test image data from export script

use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use std.env.all;

entity cnn_clean_tb is
end cnn_clean_tb;

architecture Behavioral of cnn_clean_tb is
    constant IMAGE_SIZE : integer := 28;
    constant CLK_PERIOD : time := 10 ns;

    -- UUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    -- Top-level input request / provider interface
    signal input_req_row   : integer := 0;
    signal input_req_col   : integer := 0;
    signal input_req_valid : std_logic := '0';
    signal input_req_ready : std_logic := '1';  -- TB always ready

    signal input_pixel : WORD := (others => '0');
    signal input_valid : std_logic := '0';
    signal input_ready : std_logic;

    -- Output interface
    signal output_guess : WORD := (others => '0');
    signal output_valid : std_logic;
    signal output_ready : std_logic := '0';

    -- For capturing last accepted request coordinates (so logs align)
    signal last_input_req_row : integer := 0;
    signal last_input_req_col : integer := 0;

    -- Test image array
    type test_image_type is array (0 to IMAGE_SIZE-1, 0 to IMAGE_SIZE-1) of integer;
    function generate_test_image return test_image_type is
        variable tmp : test_image_type;
    begin
        for r in 0 to IMAGE_SIZE-1 loop
            for c in 0 to IMAGE_SIZE-1 loop
                tmp(r,c) := TEST_IMAGE_DATA(r,c);
            end loop;
        end loop;
        return tmp;
    end function;

    constant test_image : test_image_type := generate_test_image;

    signal test_done : boolean := false;
    signal sim_cycle : integer := 0;

begin
    -- Instantiate clean top-level (cnn_top)
    uut: entity work.cnn_top
        generic map (
            IMAGE_SIZE => IMAGE_SIZE
        )
        port map (
            clk => clk,
            rst => rst,

            input_req_row   => input_req_row,
            input_req_col   => input_req_col,
            input_req_valid => input_req_valid,
            input_req_ready => input_req_ready,

            input_pixel => input_pixel,
            input_valid => input_valid,
            input_ready => input_ready,

            output_guess => output_guess,
            output_valid => output_valid,
            output_ready => output_ready
        );

    -- Clock
    clk_proc: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- Sim cycle counter
    sim_cycle_proc: process(clk)
    begin
        if rising_edge(clk) then
            if not test_done then
                sim_cycle <= sim_cycle + 1;
            end if;
        end if;
    end process;

    -- Input provider process (responds to input_req)
    input_provider: process(clk)
        variable pending : boolean := false;
        variable r_buf : integer := 0;
        variable c_buf : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                input_req_ready <= '0';
                input_valid <= '0';
                pending := false;
            else
                input_req_ready <= '0';
                input_valid <= '0';

                if input_req_valid = '1' and not pending then
                    input_req_ready <= '1';
                    r_buf := input_req_row;
                    c_buf := input_req_col;
                    last_input_req_row <= r_buf;
                    last_input_req_col <= c_buf;
                    pending := true;
                end if;

                if pending then
                    if r_buf >= 0 and r_buf < IMAGE_SIZE and c_buf >= 0 and c_buf < IMAGE_SIZE then
                        input_pixel <= std_logic_vector(to_unsigned(test_image(r_buf,c_buf), 8));
                    else
                        input_pixel <= (others => '0');
                    end if;
                    input_valid <= '1';
                    if input_ready = '1' then
                        pending := false;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- (monitor removed as per request; test_proc reports final results)

    -- Test sequence
    test_proc: process
        variable guess : integer := 0;
    begin
        -- Reset and startup
        rst <= '1';
        output_ready <= '0';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD * 5;

        -- Indicate we're ready to accept final classification and wait for it
        output_ready <= '1';
        wait until output_valid = '1';
        wait until rising_edge(clk);

        -- Read guess and print single-line result: guess + correctness
        guess := to_integer(unsigned(output_guess));
        if guess = TEST_IMAGE_LABEL then
            report "FINAL_GUESS: " & integer'image(guess) & " CORRECT";
        else
            report "FINAL_GUESS: " & integer'image(guess) & " INCORRECT; expected " & integer'image(TEST_IMAGE_LABEL);
        end if;

        -- Stop accepting further outputs and finish
        output_ready <= '0';
        wait for CLK_PERIOD * 20;
        test_done <= true;
        std.env.stop(0);
        wait;
    end process;

end Behavioral;
