library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_slave_mode0 is
    port (
        clk      : in  std_logic;  -- FPGA system clock
        rst_n    : in  std_logic;  -- Active low reset
        sclk     : in  std_logic;  -- SPI clock from master
        mosi     : in  std_logic;  -- Master Out Slave In
        miso     : out std_logic;  -- Master In Slave Out
        ss_n     : in  std_logic;  -- Slave Select (active low)
        data_in  : in  std_logic_vector(7 downto 0); -- Data to send
        data_out : out std_logic_vector(7 downto 0); -- Data received
        data_valid : out std_logic;                  -- Pulses high for 1 clk after 8 bits
        ack      : out std_logic                     -- Pulses high for 1 clk after 8 bits
    );
end spi_slave_mode0;

architecture Behavioral of spi_slave_mode0 is
    signal sclk_sync      : std_logic_vector(2 downto 0) := (others => '0');
    signal ss_n_sync      : std_logic_vector(2 downto 0) := (others => '1');
    signal sclk_rising    : std_logic := '0';
    signal sclk_falling   : std_logic := '0';
    signal ss_active      : std_logic := '0';
    signal bit_cnt        : integer range 0 to 7 := 0;
    signal rx_shift       : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_shift       : std_logic_vector(7 downto 0) := (others => '0');
    signal miso_reg       : std_logic := '0';
    signal data_valid_i   : std_logic := '0';
    signal ack_i          : std_logic := '0';
begin
    -- Synchronize SCLK and SS_N to clk domain
    process(clk)
    begin
        if rising_edge(clk) then
            sclk_sync <= sclk_sync(1 downto 0) & sclk;
            ss_n_sync <= ss_n_sync(1 downto 0) & ss_n;
        end if;
    end process;

    -- Edge detection and SPI logic
    process(clk)
    begin
        if rising_edge(clk) then
            -- Default outputs
            data_valid_i <= '0';
            ack_i <= '0';

            -- Edge detection
            sclk_rising  <= '0';
            sclk_falling <= '0';
            if sclk_sync(2 downto 1) = "01" then
                sclk_rising <= '1';
            elsif sclk_sync(2 downto 1) = "10" then
                sclk_falling <= '1';
            end if;

            -- Slave select active
            if ss_n_sync(2) = '0' then
                ss_active <= '1';
            else
                ss_active <= '0';
            end if;

            if ss_active = '0' then
                bit_cnt <= 0;
                rx_shift <= (others => '0');
                tx_shift <= data_in;
                miso_reg <= '0';
            else
                -- SPI Mode 0: sample MOSI on SCLK rising, update MISO on SCLK falling
                if sclk_rising = '1' then
                    rx_shift <= rx_shift(6 downto 0) & mosi;
                    if bit_cnt = 7 then
                        data_out <= rx_shift(6 downto 0) & mosi;
                        data_valid_i <= '1';
                        ack_i <= '1';
                        bit_cnt <= 0;
                        tx_shift <= data_in;
                    else
                        bit_cnt <= bit_cnt + 1;
                    end if;
                end if;
                if sclk_falling = '1' then
                    miso_reg <= tx_shift(7 - bit_cnt);
                end if;
            end if;
        end if;
    end process;

    miso       <= miso_reg;
    data_valid <= data_valid_i;
    ack        <= ack_i;
end Behavioral;