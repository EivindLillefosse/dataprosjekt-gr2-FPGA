----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Martin Brekke Nilsen
-- 
-- Create Date: 30.10.2025 12:15:37
-- Design Name: 
-- Module Name: SPI_memory_controller - Behavioral
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
use work.types_pkg.ALL;
use IEEE.NUMERIC_STD.ALL;



entity SPI_top is
    Generic (
       
        IMAGE_WIDTH : integer := 28;
        BUFFER_SIZE : integer := IMAGE_WIDTH*IMAGE_WIDTH;
        WORD_SIZE : integer := 8
    );
    Port ( 
            clk       : in  std_logic;
            rst       : in  std_logic;

          -- USER INTERFACE
            DATA_OUT_COL   : in  integer;
            DATA_OUT_ROW   : in  integer;
            DATA_IN      : in  std_logic_vector(WORD_SIZE-1 downto 0); 
            DATA_OUT     : out std_logic_vector(WORD_SIZE-1 downto 0); 

          -- Handshakes
            COL_ROW_REQ_READY : out std_logic;
            COL_ROW_REQ_VALID : in  std_logic;
            DATA_IN_VALID  : in  std_logic; 
            DATA_IN_READY  : out std_logic; 
            DATA_OUT_VALID : out std_logic; 
            DATA_OUT_READY : in  std_logic; 

          -- SPI INTERFACE
            SCLK     : in  std_logic; 
            CS_N     : in  std_logic;
            MOSI     : in  std_logic; 
            MISO     : out std_logic;
            
          -- VGA INTERFACE
            VGA_HS_O : out std_logic;
            VGA_VS_O : out std_logic;
            VGA_R    : out std_logic_vector(3 downto 0);
            VGA_G    : out std_logic_vector(3 downto 0);
            VGA_B    : out std_logic_vector(3 downto 0);

            OUTPUT_GUESS : in WORD
    );

          
end SPI_top;


architecture Behavioral of SPI_top is

signal data_out_spi_in_memory : std_logic_vector(WORD_SIZE-1 downto 0) := (others => '0');
signal valid_out_spi_in_memory : std_logic := '0';
signal VGA_ADDR : std_logic_vector(9 downto 0);
signal VGA_DATA : std_logic_vector(7 downto 0);
signal VGA_FRAME_START : std_logic;

  
begin


controller_memory_inst : entity work.SPI_memory_controller
  GENERIC MAP (
    IMAGE_WIDTH => IMAGE_WIDTH,
    BUFFER_SIZE => BUFFER_SIZE
    
  )
  PORT MAP (
    clk             => clk,
    rst             => rst,
    data_in         => data_out_spi_in_memory,
    data_in_valid   => valid_out_spi_in_memory,
    data_in_ready   => open,
    
    data_out        => DATA_OUT,
    data_out_valid  => DATA_OUT_VALID,
    data_out_ready  => DATA_OUT_READY,
    data_out_col    => DATA_OUT_COL,
    data_out_row    => DATA_OUT_ROW,
    col_row_req_ready => COL_ROW_REQ_READY,
    col_row_req_valid => COL_ROW_REQ_VALID,

    vga_addr       => VGA_ADDR,
    vga_data       => VGA_DATA,
    vga_frame_start => VGA_FRAME_START

  );

SPI_slave_inst : entity work.SPI_SLAVE
  GENERIC MAP (
    WORD_SIZE => 8
  )
  PORT MAP (
    CLK         => clk,
    RESET       => rst,
    
    SCLK        => SCLK,
    CS_N        => CS_N,
    MOSI        => MOSI,
    MISO        => MISO,
    
    DATA_IN     => DATA_IN,
    DATA_IN_VALID => DATA_IN_VALID,
    DATA_IN_READY => DATA_IN_READY,
    
    DATA_OUT    => data_out_spi_in_memory,
    DATA_OUT_VALID => valid_out_spi_in_memory
  );

VGA_inst : entity work.vga_top
  GENERIC MAP (
    IMAGE_WIDTH => IMAGE_WIDTH,
    IMAGE_HEIGHT => IMAGE_WIDTH
  )
  PORT MAP (
    CLK_I       => clk,
    RST         => rst,
    
    VGA_HS_O    => VGA_HS_O,
    VGA_VS_O    => VGA_VS_O,
    VGA_R       => VGA_R,
    VGA_G       => VGA_G,
    VGA_B       => VGA_B,

    spi_vga_addr => VGA_ADDR,
    spi_vga_data => VGA_DATA,
    vga_frame_start => VGA_FRAME_START,

    output_guess => OUTPUT_GUESS
  );  

end Behavioral;

