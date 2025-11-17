----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse, Martin Brekke Nilsen, Nikolai Sandvik Nore
--
-- Create Date: 14.11.2025
-- Design Name: CNN Accelerator
-- Module Name: cnn_tb - Behavioral
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

entity cnn_tb is
end cnn_tb;

architecture Behavioral of cnn_tb is
    constant IMAGE_SIZE : integer := 28;
    constant CLK_PERIOD : time := 10 ns;

    -- UUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    -- Top-level input request / provider interface
    signal input_req_row   : integer := 0;
    signal input_req_col   : integer := 0;
    signal input_req_valid : std_logic := '0';
    signal input_req_ready : std_logic := '1';  -- TB always ready (drive high)

    signal input_pixel : WORD := (others => '0');
    signal input_valid : std_logic := '0';
    signal input_ready : std_logic;

    -- Output interface
    signal output_guess : WORD := (others => '0');
    signal output_valid : std_logic;
    signal output_ready : std_logic := '1';  -- always ready to accept final output

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

    -- Second test image embedded directly (aircraft carrier sample 0)
    constant test_image2 : test_image_type := (
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   5,  16,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,  83, 248, 253, 101,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,  50, 252, 255, 184,  33,  18,  12,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0, 106, 255, 192, 255, 255, 254,  74,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0, 101, 255, 246, 252, 231, 255,  80,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,  14, 114, 136, 190, 253, 214, 224, 229, 255, 177, 136, 136, 136, 136, 136, 136, 136, 136, 136, 128, 112,  97,  82,  67,  48,   2,   0),
        (  0,  93, 255, 243, 239, 242, 238, 238, 240, 247, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 249, 255, 255, 255, 255, 255,  94,   0),
        (  0,  22, 251, 125,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   9,  24,  39,  84, 255,  87,   0),
        (  0,   0, 181, 248, 191, 159,  68,  51,  51,  34,  34,  23,  17,  11,   0,   0,   0,   0,   0,   0,   0,   6,  24,  43, 107, 255,  61,   0),
        (  0,   0,  32, 133, 208, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 238, 238, 227, 225, 243, 255, 255, 255, 255, 233,  21,   0),
        (  0,   0,   0,   0,  14, 174, 215, 227, 236, 244, 255, 255, 255, 255, 188, 125, 136, 137, 153, 151, 133, 115,  97,  79,  58,   6,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  12,  23,  34,   4,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0),
        (  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0)
    );

    -- Select which test image the input provider uses: 0 => test_image, 1 => test_image2
    signal current_image : integer := 0;

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
                        if current_image = 0 then
                            input_pixel <= std_logic_vector(to_unsigned(test_image(r_buf,c_buf), 8));
                        else
                            input_pixel <= std_logic_vector(to_unsigned(test_image2(r_buf,c_buf), 8));
                        end if;
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

        -- Run 1: wait for final classification
        report "Starting run 1...";
        wait until output_valid = '1';
        wait until rising_edge(clk);
        guess := to_integer(unsigned(output_guess));
        report "Run 1 FINAL_GUESS: " & integer'image(guess);

        -- Small gap before next run
        wait for CLK_PERIOD * 10;

    -- Run 2: run again without reset (use second test image)
    report "Starting run 2 (no reset) - switching to test_image2...";
    current_image <= 1;
    wait for CLK_PERIOD; -- allow provider to sample the flag
    wait until output_valid = '1';
    wait until rising_edge(clk);
    guess := to_integer(unsigned(output_guess));
    report "Run 2 FINAL_GUESS: " & integer'image(guess);

    -- Small gap before third run
    wait for CLK_PERIOD * 10;

    -- Restore default test image for subsequent runs
    current_image <= 0;
    wait for CLK_PERIOD;

    -- Run 3: third run without reset
    report "Starting run 3 (no reset)...";
    wait until output_valid = '1';
    wait until rising_edge(clk);
    guess := to_integer(unsigned(output_guess));
    report "Run 3 FINAL_GUESS: " & integer'image(guess);

    -- Now reset and perform a final run after reset
    report "Resetting and performing run 4...";
    rst <= '1';
    wait for CLK_PERIOD * 2;
    rst <= '0';
    wait for CLK_PERIOD * 5;

    -- Run 4: after reset
    wait until output_valid = '1';
    wait until rising_edge(clk);
    guess := to_integer(unsigned(output_guess));
    report "Run 4 FINAL_GUESS: " & integer'image(guess);

        -- Finish
        wait for CLK_PERIOD * 20;
        test_done <= true;
        std.env.stop(0);
        wait;
    end process;

end Behavioral;
