----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Martin Brekke Nilsen, Eivind Lillefosse, Nikolai Sandvik Nore
-- 
-- Create Date: 31.10.2025
-- Design Name: CNN Accelerator
-- Module Name: cnn_top
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Description: Top-level module for CNN Accelerator
--
----------------------------------------------------------------------------------

library IEEE;   
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity top is
    generic (
        IMAGE_WIDTH : integer := 28
    );

    Port ( 
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- SPI INTERFACE
        SCLK     : in  std_logic; 
        CS_N     : in  std_logic;
        MOSI     : in  std_logic; 
        MISO     : out std_logic;
        
        -- Debug output to prevent optimization
       
        VGA_HS_O : out std_logic;
        VGA_VS_O : out std_logic;
        VGA_R    : out std_logic_vector(3 downto 0);
        VGA_G    : out std_logic_vector(3 downto 0);
        VGA_B    : out std_logic_vector(3 downto 0)

    );
end top;

architecture Behavioral of top is
    signal valid_out_spi_in_cnn : std_logic;
    signal valid_out_cnn_in_spi : std_logic;

    signal ready_out_spi_in_cnn : std_logic;
    signal ready_out_cnn_in_spi : std_logic;

    signal data_col : integer;
    signal data_row : integer;

    signal data_tx : std_logic_vector(7 downto 0);
    signal data_rx : std_logic_vector(7 downto 0);

    signal col_row_req_ready : std_logic;
    signal col_row_req_valid : std_logic;
    
  
begin 

SPI_inst : entity work.SPI_top
    generic map (
        IMAGE_WIDTH => IMAGE_WIDTH
    )
    port map (
        clk           => clk,
        rst           => rst,
        
        -- USER INTERFACE
        DATA_OUT_COL   => data_col, 
        DATA_OUT_ROW   => data_row, 
        DATA_IN      => data_tx, 
        DATA_OUT     => data_rx, 

        -- Handshakes
        DATA_IN_VALID  => valid_out_cnn_in_spi, 
        DATA_IN_READY  => ready_out_cnn_in_spi, 
        DATA_OUT_VALID => valid_out_spi_in_cnn, 
        DATA_OUT_READY => ready_out_spi_in_cnn,
        COL_ROW_REQ_READY => col_row_req_ready,
        COL_ROW_REQ_VALID => col_row_req_valid,

        -- SPI INTERFACE
        SCLK         => SCLK,
        CS_N         => CS_N,
        MOSI         => MOSI,
        MISO         => MISO,

        --VGA INTERFACE
        VGA_HS_O    => VGA_HS_O,
        VGA_VS_O    => VGA_VS_O,
        VGA_R       => VGA_R,
        VGA_G       => VGA_G,
        VGA_B       => VGA_B
    );

CNN_inst : entity work.CNN_top
    generic map (
        IMAGE_SIZE => IMAGE_WIDTH
    )
    port map (
        clk       => clk,
        rst       => rst,
       

        input_pixel      => data_rx,
        output_guess     => data_tx,
        input_valid      => valid_out_spi_in_cnn,
        input_ready      => ready_out_spi_in_cnn,
        output_valid     => valid_out_cnn_in_spi,
        output_ready     => ready_out_cnn_in_spi,

        input_req_ready  => col_row_req_ready,
        input_req_valid  => col_row_req_valid,
        input_req_row        => data_row,
        input_req_col        => data_col
    );


end Behavioral;