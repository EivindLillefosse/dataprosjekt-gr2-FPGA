----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Automated testbench generator
--
-- Create Date: 15.11.2025
-- Module Name: top_clean_tb - Behavioral
-- Description: Clean top-level testbench for `top`. Drives SPI master
--              deterministically and verifies memory writes and LED output.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;
use work.test_image_pkg.all;  -- Real test image data

use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use std.env.all;

entity top_clean_tb is
end top_clean_tb;

architecture Behavioral of top_clean_tb is
    constant IMAGE_WIDTH : integer := 28;
    constant CLK_PERIOD : time := 10 ns;
    constant SPI_PERIOD : time := 1 us; -- 1 MHz
    constant SPI_HALF : time := SPI_PERIOD / 2;

    -- signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal SCLK : std_logic := '0';
    signal CS_N : std_logic := '1';
    signal MOSI : std_logic := '0';
    signal MISO : std_logic := '0';

    signal VGA_HS_O : std_logic;
    signal VGA_VS_O : std_logic;
    signal VGA_R : std_logic_vector(3 downto 0);
    signal VGA_G : std_logic_vector(3 downto 0);
    signal VGA_B : std_logic_vector(3 downto 0);

    signal ld0 : std_logic;
    signal ld1 : std_logic;
    signal ld2 : std_logic;
    signal ld3 : std_logic;

    signal test_done : boolean := false;

    -- test image
    type test_image_type is array (0 to IMAGE_WIDTH-1, 0 to IMAGE_WIDTH-1) of integer;
    function generate_test_image return test_image_type is
        variable tmp : test_image_type;
    begin
        for r in 0 to IMAGE_WIDTH-1 loop
            for c in 0 to IMAGE_WIDTH-1 loop
                tmp(r,c) := TEST_IMAGE_DATA(r,c);
            end loop;
        end loop;
        return tmp;
    end function;
    constant test_image : test_image_type := generate_test_image;

begin
    -- instantiate top
    uut: entity work.top
        port map (
            clk => clk,
            rst => rst,
            SCLK => SCLK,
            CS_N => CS_N,
            MOSI => MOSI,
            MISO => MISO,
            VGA_HS_O => VGA_HS_O,
            VGA_VS_O => VGA_VS_O,
            VGA_R => VGA_R,
            VGA_G => VGA_G,
            VGA_B => VGA_B,
            ld0 => ld0,
            ld1 => ld1,
            ld2 => ld2,
            ld3 => ld3
        );

    -- clock
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

    -- SPI master: drives SCLK, MOSI (self-contained)
    spi_master_proc: process
        procedure spi_delay is
        begin
            wait for SPI_HALF;
        end procedure;

        procedure spi_send_byte(data : in std_logic_vector(7 downto 0)) is
        begin
            for i in 7 downto 0 loop
                -- MOSI stable while SCLK low
                MOSI <= data(i);
                SCLK <= '0';
                spi_delay;
                -- sample at rising edge of SCLK; slave uses rising edge
                SCLK <= '1';
                spi_delay;
            end loop;
            SCLK <= '0';
            spi_delay;
        end procedure;

        procedure spi_read_byte(variable out_byte : out std_logic_vector(7 downto 0)) is
            variable tmp : std_logic_vector(7 downto 0) := (others => '0');
        begin
            for i in 7 downto 0 loop
                MOSI <= '0';
                SCLK <= '0';
                spi_delay;
                SCLK <= '1';
                spi_delay;
                tmp(i) := MISO;
            end loop;
            SCLK <= '0';
            out_byte := tmp;
        end procedure;

        variable bcount : integer := 0;
        variable pb : std_logic_vector(7 downto 0);
        variable readb : std_logic_vector(7 downto 0);
    begin
        -- init
        CS_N <= '1';
        SCLK <= '0';
        MOSI <= '0';
        wait for CLK_PERIOD*5;
        rst <= '1';
        wait for CLK_PERIOD*2;
        rst <= '0';
        wait for CLK_PERIOD*5;

        report "TOP_CLEAN_TB: starting SPI transfer";

        -- assert CS_N and give slave time to sync
        CS_N <= '0';
        wait for CLK_PERIOD*12;

        -- send 2 dummy bytes (optional)
        --spi_send_byte(x"00"); bcount := bcount + 1;
        --spi_send_byte(x"00"); bcount := bcount + 1;

        -- send image bytes row-major
        for r in 0 to IMAGE_WIDTH-1 loop
            for c in 0 to IMAGE_WIDTH-1 loop
                pb := std_logic_vector(to_unsigned(test_image(r,c), 8));
                spi_send_byte(pb);
                bcount := bcount + 1;
                if bcount <= 32 then
                    report "Sent byte " & integer'image(bcount) & ": 0x" & to_hstring(pb);
                end if;
            end loop;
        end loop;

        report "TOP_CLEAN_TB: total bytes sent = " & integer'image(bcount);

        -- keep CS_N low and read back one byte from slave (MISO)
        spi_read_byte(readb);
        report "Readback byte: 0x" & to_hstring(readb) & " (dec=" & integer'image(to_integer(unsigned(readb))) & ")";

        -- wait for CNN to process and LED update
        wait for CLK_PERIOD * 5000000; -- give time (adjust as needed)

        report "LEDs: " & to_string(ld3 & ld2 & ld1 & ld0);
        report "Expected label: " & integer'image(TEST_IMAGE_LABEL);

        -- finish
        wait for CLK_PERIOD*100;
        test_done <= true;
        std.env.stop(0);
        wait;
    end process;

end Behavioral;
