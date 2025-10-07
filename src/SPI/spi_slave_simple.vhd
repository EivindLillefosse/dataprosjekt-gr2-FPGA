library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Simple SPI Slave Mode 0 (CPOL=0, CPHA=0)
-- This is a basic 8-bit SPI slave that's easy to understand
entity spi_slave_simple is
    port (
        -- System signals
        clk         : in  std_logic;  -- FPGA system clock (fast)
        rst_n       : in  std_logic;  -- Active low reset
        
        -- SPI interface signals (from master)
        sclk        : in  std_logic;  -- SPI clock from master
        mosi        : in  std_logic;  -- Master Out Slave In (data from master)
        miso        : out std_logic;  -- Master In Slave Out (data to master)
        ss_n        : in  std_logic;  -- Slave Select (active low)
        
        -- Enhanced data interface
        data_in     : in  std_logic_vector(7 downto 0);   -- Data to send to master
        data_out    : out std_logic_vector(7 downto 0);   -- Data received from master
        data_ready  : out std_logic;                       -- Pulses when new data is ready
        byte_ack    : out std_logic                        -- ACK pulse when complete byte received
    );
end spi_slave_simple;

architecture Behavioral of spi_slave_simple is
    -- Synchronize SPI signals to avoid metastability
    signal sclk_sync : std_logic_vector(1 downto 0) := "00";
    signal ss_n_sync : std_logic_vector(1 downto 0) := "11";
    
    -- Edge detection for SCLK
    signal sclk_prev : std_logic := '0';
    
    -- Shift registers for 8-bit data
    signal rx_shift : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_shift : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Bit counter (0 to 7 for 8 bits)
    signal bit_count : unsigned(2 downto 0) := (others => '0');
    
    -- Output registers
    signal miso_reg : std_logic := '0';
    signal data_ready_reg : std_logic := '0';
    signal byte_ack_reg : std_logic := '0';
    
begin
    -- Connect outputs
    miso <= miso_reg;
    data_ready <= data_ready_reg;
    byte_ack <= byte_ack_reg;
    
    -- Main SPI process
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                -- Reset everything
                sclk_sync <= "00";
                ss_n_sync <= "11";
                sclk_prev <= '0';
                bit_count <= (others => '0');
                rx_shift <= (others => '0');
                tx_shift <= (others => '0');
                miso_reg <= '0';
                data_ready_reg <= '0';
                byte_ack_reg <= '0';
                data_out <= (others => '0');
                
            else
                -- Synchronize SPI signals (2 flip-flops to prevent metastability)
                sclk_sync <= sclk_sync(0) & sclk;
                ss_n_sync <= ss_n_sync(0) & ss_n;
                sclk_prev <= sclk_sync(1);
                
                -- Default: pulse signals are just pulses
                data_ready_reg <= '0';
                byte_ack_reg <= '0';
                
                -- SPI Mode 0 logic: CPOL=0 (idle low), CPHA=0 (sample on first edge)
                
                if ss_n_sync(1) = '1' then
                    -- Slave not selected - reset and prepare
                    bit_count <= (others => '0');
                    rx_shift <= (others => '0');
                    tx_shift <= data_in;        -- Load data to transmit
                    miso_reg <= data_in(7);     -- Put first bit (MSB) on MISO
                    
                else
                    -- Slave is selected - do SPI transaction
                    
                    -- SCLK rising edge: sample MOSI (master outputs data)
                    if sclk_sync(1) = '1' and sclk_prev = '0' then
                        -- Shift in new bit from MOSI
                        rx_shift <= rx_shift(6 downto 0) & mosi;
                        
                        -- Check if we've received 8 bits
                        if bit_count = 7 then
                            -- Complete byte received - generate ACK and ready signals
                            data_out <= rx_shift(6 downto 0) & mosi;  -- Output the complete byte
                            data_ready_reg <= '1';  -- Signal that data is ready
                            byte_ack_reg <= '1';    -- ACK pulse for complete byte
                            bit_count <= (others => '0');  -- Reset for next byte
                            -- Load next data to transmit
                            tx_shift <= data_in;
                            miso_reg <= data_in(7);
                        else
                            -- Still receiving bits
                            bit_count <= bit_count + 1;
                        end if;
                    end if;
                    
                    -- SCLK falling edge: update MISO (slave outputs data)
                    if sclk_sync(1) = '0' and sclk_prev = '1' then
                        -- Shift out next bit on MISO
                        tx_shift <= tx_shift(6 downto 0) & '0';  -- Shift left
                        miso_reg <= tx_shift(6);  -- Next bit to output
                    end if;
                    
                end if;
            end if;
        end if;
    end process;
    
end Behavioral;