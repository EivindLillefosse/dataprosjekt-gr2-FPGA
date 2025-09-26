----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: 
-- Module Name: top - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    Port ( 
        clk      : in  std_logic;  -- System clock
        rst_n    : in  std_logic;  -- Reset (active low)
        sclk     : in  std_logic;  -- SPI clock
        mosi     : in  std_logic;  -- SPI MOSI
        miso     : out std_logic;  -- SPI MISO
        ss_n     : in  std_logic;  -- SPI Slave Select
        led      : out std_logic_vector(7 downto 0) -- LEDs to show received data
    );
end top;

architecture Behavioral of top is
    signal tx_data     : std_logic_vector(7 downto 0) := x"A5"; -- Data to send
    signal rx_data     : std_logic_vector(7 downto 0);
    signal rx_valid    : std_logic;
    signal tx_ready    : std_logic;
    
begin

    -- Instantiate the bulletproof SPI slave
    spi_inst: entity work.spi_slave_bulletproof
        port map (
            clk        => clk,
            rst_n      => rst_n,
            spi_clk    => sclk,
            spi_mosi   => mosi,
            spi_miso   => miso,
            spi_cs_n   => ss_n,
            tx_data    => tx_data,
            rx_data    => rx_data,
            rx_valid   => rx_valid,
            tx_ready   => tx_ready
        );
    
    -- Connect received data to LEDs for visibility
    led <= rx_data;

end Behavioral;
