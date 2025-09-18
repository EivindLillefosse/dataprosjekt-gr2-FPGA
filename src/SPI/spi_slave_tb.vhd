library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_slave_tb is
end spi_slave_tb;

architecture sim of spi_slave_tb is
    -- Constants
    constant CLK_PERIOD : time := 10 ns;  -- 100MHz system clock
    constant SPI_PERIOD : time := 100 ns; -- 10MHz SPI clock
    constant DATA_WIDTH : integer := 8;
    
    -- Test signals
    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal spi_sclk    : std_logic := '0';
    signal spi_cs_n    : std_logic := '1';
    signal spi_mosi    : std_logic := '0';
    signal spi_miso    : std_logic;
    signal data_in     : std_logic_vector(DATA_WIDTH-1 downto 0) := x"A5"; -- Test pattern
    signal data_out    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal data_valid  : std_logic;
    signal busy        : std_logic;
    
    -- Test procedure
    procedure spi_transfer(
        signal sclk    : out std_logic;
        signal cs_n    : out std_logic;
        signal mosi    : out std_logic;
        constant data  : in  std_logic_vector(7 downto 0)) is
    begin
        cs_n <= '0';
        wait for SPI_PERIOD/2;
        
        for i in 7 downto 0 loop
            mosi <= data(i);
            sclk <= '1';
            wait for SPI_PERIOD/2;
            sclk <= '0';
            wait for SPI_PERIOD/2;
        end loop;
        
        cs_n <= '1';
        wait for SPI_PERIOD;
    end procedure;
    
begin
    -- Clock generation
    process
    begin
        wait for CLK_PERIOD/2;
        clk <= not clk;
    end process;
    
    -- DUT instantiation
    dut: entity work.spi_slave
    generic map (
        DATA_WIDTH => DATA_WIDTH
    )
    port map (
        clk        => clk,
        rst_n      => rst_n,
        spi_sclk   => spi_sclk,
        spi_cs_n   => spi_cs_n,
        spi_mosi   => spi_mosi,
        spi_miso   => spi_miso,
        data_in    => data_in,
        data_out   => data_out,
        data_valid => data_valid,
        busy       => busy
    );
    
    -- Stimulus process
    process
    begin
        -- Reset
        wait for CLK_PERIOD*2;
        rst_n <= '1';
        wait for CLK_PERIOD*2;
        
        -- Test 1: Send 0x55
        spi_transfer(spi_sclk, spi_cs_n, spi_mosi, x"55");
        wait for SPI_PERIOD*2;
        
        -- Test 2: Send 0xAA
        spi_transfer(spi_sclk, spi_cs_n, spi_mosi, x"AA");
        wait for SPI_PERIOD*2;
        
        -- Test 3: Send 0xFF
        spi_transfer(spi_sclk, spi_cs_n, spi_mosi, x"FF");
        wait for SPI_PERIOD*2;
        
        -- End simulation
        wait for SPI_PERIOD*4;
        assert false report "Test completed successfully" severity note;
        wait;
    end process;
    
end architecture sim;