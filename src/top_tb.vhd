----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Martin Brekke Nilsen, Eivind Lillefosse, Nikolai Sandvik Nore
--
-- Create Date: 15.11.2025
-- Design Name: CNN Accelerator
-- Module Name: top_tb - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Top-level testbench for complete system (SPI + CNN + VGA)
--              Uses exported test image data to verify end-to-end functionality
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

entity top_tb is
end top_tb;

architecture Behavioral of top_tb is
    constant IMAGE_WIDTH : integer := 28;
    constant CLK_PERIOD : time := 10 ns;
    constant SPI_PERIOD : time := 1 us;  -- 1 MHz SPI clock
    constant SPI_HALF_PERIOD : time := SPI_PERIOD / 2;

    -- UUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    -- SPI interface
    signal SCLK : std_logic := '0';
    signal CS_N : std_logic := '1';
    signal MOSI : std_logic := '0';
    signal MISO : std_logic;

    -- VGA interface
    signal VGA_HS_O : std_logic;
    signal VGA_VS_O : std_logic;
    signal VGA_R : std_logic_vector(3 downto 0);
    signal VGA_G : std_logic_vector(3 downto 0);
    signal VGA_B : std_logic_vector(3 downto 0);

    -- LED outputs
    signal ld0 : std_logic;
    signal ld1 : std_logic;
    signal ld2 : std_logic;
    signal ld3 : std_logic;

    -- Test control
    signal test_done : boolean := false;
    signal spi_transmission_done : boolean := false;

    -- Test image array
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
    -- Instantiate top-level design
    uut: entity work.top
        generic map (
            IMAGE_WIDTH => IMAGE_WIDTH
        )
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

    -- System clock generator (100 MHz)
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

    -- Continuous SPI clock generator
    -- Start toggling SCLK only after CS_N has been low for at least 10 system clock cycles
    spi_clk_proc: process
    begin
        -- Ensure SCLK starts low
        SCLK <= '0';
        -- Wait for CS_N to go low (transaction start)
        wait until CS_N = '0';
        -- Wait for 10 system clock cycles to ensure slave is ready
        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;
        -- Now run continuous SCLK
        while not test_done loop
            wait for SPI_HALF_PERIOD;
            SCLK <= not SCLK;
        end loop;
        wait;
    end process;

    -- SPI Master process: sends test image over SPI
    spi_master_proc: process
        -- Send one byte over SPI (SCLK runs continuously, just set MOSI at right times)
        procedure spi_send_byte(data : in std_logic_vector(7 downto 0)) is
        begin
            -- Align to SCLK low before starting
            wait until SCLK = '0';
            for i in 7 downto 0 loop
                -- Drive MOSI while SCLK is low so it is stable at rising edge
                MOSI <= data(i);
                -- Wait for rising edge where slave samples MOSI
                wait until SCLK = '1';
                -- Wait for falling edge to prepare next bit
                wait until SCLK = '0';
            end loop;
            -- Leave MOSI low after the byte
            MOSI <= '0';
        end procedure;
        
        variable pixel_value : integer;
        variable pixel_byte : std_logic_vector(7 downto 0);
        variable byte_count : integer := 0;
        variable read_byte : std_logic_vector(7 downto 0) := (others => '0');
    begin
        -- Initial state
        CS_N <= '1';
        MOSI <= '0';
        
        -- Wait for reset to complete
        wait until rst = '0';
        wait for CLK_PERIOD * 10;
        
        report "========================================";
        report "Starting SPI transmission of test image";
        report "Image size: " & integer'image(IMAGE_WIDTH) & "x" & integer'image(IMAGE_WIDTH);
        report "Expected label: " & integer'image(TEST_IMAGE_LABEL);
        report "========================================";
        
        -- Assert chip select (active low)
        -- Do not wait on SCLK here (avoids circular dependency with spi_clk_proc)
        CS_N <= '0';
        -- Give the slave time: wait 12 system clock cycles before starting transfers
        for i in 1 to 12 loop
            wait until rising_edge(clk);
        end loop;
        
        -- Send 2 dummy bytes to prime the SPI slave pipeline
        -- (last_bit_en is registered, causing a 2-byte delay in data_out_valid)
        spi_send_byte(x"00");
        byte_count := byte_count + 1;
        spi_send_byte(x"00");
        byte_count := byte_count + 1;
        
        -- Send entire 28x28 image row by row
        for row in 0 to IMAGE_WIDTH-1 loop
            for col in 0 to IMAGE_WIDTH-1 loop
                pixel_value := test_image(row, col);
                pixel_byte := std_logic_vector(to_unsigned(pixel_value, 8));
                
                byte_count := byte_count + 1;
                spi_send_byte(pixel_byte);
                
                -- Report progress every 100 pixels
                if ((row * IMAGE_WIDTH + col + 1) mod 100) = 0 then
                    report "Sent " & integer'image(row * IMAGE_WIDTH + col + 1) & " pixels";
                end if;
            end loop;
        end loop;
        
        report "Total bytes sent via SPI: " & integer'image(byte_count);

        -- Small per-byte debug prints for the first bytes to verify timing
        -- (We printed progress every 100 earlier; print first 32 explicitly)
        report "First bytes were sent. Printing first 32 send events in simulation log.";

        -- Note: we printed each sent byte inline during the send loop for diagnostic

        -- Keep MOSI at 0 and KEEP CS_N LOW so master can read back MISO
        MOSI <= '0';

        -- Explicit readback: clock 8 dummy bits (MOSI=0) while CS_N is low and capture MISO
        -- Read one byte from slave (MISO)
        read_byte := (others => '0');
        for i in 7 downto 0 loop
            -- Align sampling to rising edge: ensure MOSI is 0 before clock
            MOSI <= '0';
            wait until SCLK = '0';
            -- small setup margin
            wait for SPI_HALF_PERIOD / 4;
            wait until SCLK = '1';
            -- sample MISO at rising edge
            read_byte(i) := MISO;
        end loop;
        report "Readback MISO byte (decimal): " & integer'image(to_integer(unsigned(read_byte))) &
               "  (bin: " & to_string(read_byte) & ")";

        report "SPI transmission complete (" & integer'image(IMAGE_WIDTH * IMAGE_WIDTH) & " pixels)";
        report "SCLK will continue running and CS_N remains low for readback (MISO)";
        spi_transmission_done <= true;
        wait;
    end process;

    -- Monitor LED outputs (CNN classification result)
    led_monitor_proc: process
        variable last_led_value : std_logic_vector(3 downto 0) := "0000";
        variable current_led_value : std_logic_vector(3 downto 0);
        variable guess : integer;
    begin
        wait until spi_transmission_done;
        wait for CLK_PERIOD * 10;
        
        report "Monitoring LED outputs for CNN classification result...";
        
        -- Monitor LEDs for changes (indicating classification complete)
        for i in 0 to 100000 loop
            wait until rising_edge(clk);
            
            current_led_value := ld3 & ld2 & ld1 & ld0;
            
            if current_led_value /= last_led_value then
                guess := to_integer(unsigned(current_led_value));
                report "LED changed to: " & integer'image(guess) & 
                       " (binary: " & to_string(current_led_value) & ")";
                last_led_value := current_led_value;
            end if;
            
            -- Exit after reasonable time
            if i = 100000 then
                report "Monitoring timeout reached";
                exit;
            end if;
        end loop;
        
        wait;
    end process;

    -- Main test control
    test_proc: process
        variable final_guess : integer;
    begin
        -- Reset sequence
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        
        report "========================================";
        report "TOP-LEVEL TESTBENCH STARTED";
        report "Testing complete CNN system via SPI";
        report "========================================";
        
        -- Wait for SPI transmission to complete
        wait until spi_transmission_done;
        
        -- Give CNN time to process the image
        -- (Conv1 + Pool1 + Conv2 + Pool2 + FC1 + FC2)
        -- Approximate cycles needed: several thousand
        wait for CLK_PERIOD * 50000000;
        
        -- Read final classification from LEDs
        final_guess := to_integer(unsigned(std_logic_vector'(ld3 & ld2 & ld1 & ld0)));
        
        report "";
        report "========================================";
        report "TEST COMPLETE";
        report "========================================";
        report "Final CNN guess (from LEDs): " & integer'image(final_guess);
        report "Expected label: " & integer'image(TEST_IMAGE_LABEL);
        
        if final_guess = TEST_IMAGE_LABEL then
            report "RESULT: CORRECT CLASSIFICATION!" severity note;
        else
            report "RESULT: INCORRECT - Expected " & integer'image(TEST_IMAGE_LABEL) & 
                   " but got " & integer'image(final_guess) severity warning;
        end if;
        report "========================================";
        
        -- End simulation
        wait for CLK_PERIOD * 100;
        test_done <= true;
        std.env.stop(0);
        wait;
    end process;

end Behavioral;
