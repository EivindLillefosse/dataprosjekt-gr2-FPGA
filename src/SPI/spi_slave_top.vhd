--------------------------------------------------------------------------------
-- Top-level wrapper for SPI_SLAVE module on Arty A7 board
-- This wrapper connects the SPI_SLAVE internal ports to test logic and LEDs
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_slave_top is
    Port (
        -- System interface
        CLK          : in  std_logic;  -- 100 MHz system clock
        RESET        : in  std_logic;  -- Reset button (active high)
        
        -- SPI interface (connected to Pmod JA)
        SCLK         : in  std_logic;  -- SPI clock from master
        CS_N         : in  std_logic;  -- Chip select (active low)
        MOSI         : in  std_logic;  -- Master Out Slave In
        MISO         : out std_logic;  -- Master In Slave Out
        
        -- Debug outputs (LEDs)
        led          : out std_logic_vector(3 downto 0);  -- Display lower 4 bits of received data
        led0_r       : out std_logic;  -- Red: data received flag
        led0_g       : out std_logic;  -- Green: ready to accept data
        led0_b       : out std_logic   -- Blue: error/status
    );
end spi_slave_top;

architecture Behavioral of spi_slave_top is

    -- Internal signals for SPI_SLAVE user interface
    signal data_in       : std_logic_vector(7 downto 0);
    signal data_in_valid : std_logic;
    signal data_in_ready : std_logic;
    signal data_out      : std_logic_vector(7 downto 0);
    signal data_out_valid: std_logic;
    
    -- Storage for received data
    signal rx_data_reg   : std_logic_vector(7 downto 0) := x"00";
    
    -- Counter for automatic TX data generation
    signal tx_counter    : unsigned(7 downto 0) := (others => '0');
    
    -- Edge detection for data_out_valid
    signal data_out_valid_prev : std_logic := '0';
    signal rx_pulse            : std_logic;

begin

    -- =========================================================================
    -- SPI_SLAVE Instance
    -- =========================================================================
    spi_slave_inst : entity work.SPI_SLAVE
        generic map (
            WORD_SIZE => 8
        )
        port map (
            CLK            => CLK,
            RESET          => RESET,
            -- SPI Interface
            SCLK           => SCLK,
            CS_N           => CS_N,
            MOSI           => MOSI,
            MISO           => MISO,
            -- User Interface
            DATA_IN        => data_in,
            DATA_IN_VALID  => data_in_valid,
            DATA_IN_READY  => data_in_ready,
            DATA_OUT       => data_out,
            DATA_OUT_VALID => data_out_valid
        );

    -- =========================================================================
    -- TX Logic: Automatically provide data to send back to master
    -- =========================================================================
    -- Simple strategy: Send an incrementing counter value
    -- When SPI slave is ready, load the next counter value
    
    tx_data_process : process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                tx_counter    <= (others => '0');
                data_in       <= x"A5";  -- Start with a test pattern
                data_in_valid <= '0';
            else
                -- Default: keep valid low
                data_in_valid <= '0';
                
                -- When slave is ready, provide new data
                if data_in_ready = '1' and data_in_valid = '0' then
                    data_in       <= std_logic_vector(tx_counter);
                    data_in_valid <= '1';
                    tx_counter    <= tx_counter + 1;
                elsif data_in_ready = '1' and data_in_valid = '1' then
                    -- Data was accepted, deassert valid next cycle
                    data_in_valid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- RX Logic: Capture received data for display
    -- =========================================================================
    
    -- Edge detection for data_out_valid (detect new received byte)
    rx_pulse <= data_out_valid and not data_out_valid_prev;
    
    rx_data_process : process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                rx_data_reg         <= x"00";
                data_out_valid_prev <= '0';
            else
                data_out_valid_prev <= data_out_valid;
                
                -- Capture new received data on rising edge of valid
                if rx_pulse = '1' then
                    rx_data_reg <= data_out;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- LED Outputs: Display status and received data
    -- =========================================================================
    
    -- Display lower 4 bits of last received byte on standard LEDs
    led <= rx_data_reg(3 downto 0);
    
    -- RGB LED status indicators
    led0_r <= data_out_valid;    -- Red: flashes when data received
    led0_g <= data_in_ready;     -- Green: shows when ready to accept TX data
    led0_b <= rx_data_reg(7);    -- Blue: shows MSB of received data

end Behavioral;
