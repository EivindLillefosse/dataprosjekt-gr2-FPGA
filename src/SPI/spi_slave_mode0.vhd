library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_slave_mode0 is
    generic (
        DATA_WIDTH : integer := 8
    );
    port (
        clk      : in  std_logic;  -- FPGA system clock
        rst_n    : in  std_logic;  -- Active low reset
        sclk     : in  std_logic;  -- SPI clock from master
        mosi     : in  std_logic;  -- Master Out Slave In
        miso     : out std_logic;  -- Master In Slave Out
        ss_n     : in  std_logic;  -- Slave Select (active low)
        data_in  : in  std_logic_vector(DATA_WIDTH-1 downto 0); -- Data to send
        data_out : out std_logic_vector(DATA_WIDTH-1 downto 0); -- Data received
        data_valid : out std_logic;  -- Pulses high for 1 clk after DATA_WIDTH bits
        ack      : out std_logic     -- Pulses high for 1 clk after DATA_WIDTH bits
    );
end spi_slave_mode0;

architecture Behavioral of spi_slave_mode0 is
    -- Reduced synchronizer depth for LUT optimization
    signal sclk_sync      : std_logic_vector(1 downto 0) := (others => '0');
    signal ss_n_sync      : std_logic_vector(1 downto 0) := (others => '1');
    
    -- Use binary counter instead of integer for better synthesis
    signal bit_cnt        : unsigned(3 downto 0) := (others => '0'); 
    
    -- Shift registers
    signal rx_shift       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal tx_shift       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- Output registers
    signal miso_reg       : std_logic := '0';
    signal data_valid_reg : std_logic := '0';
    signal ack_reg        : std_logic := '0';
    
    -- Optimized edge detection
    signal sclk_prev      : std_logic := '0';
    signal ss_active      : std_logic := '0';
    
begin
    -- Main SPI process - optimized for fewer LUTs
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                -- Reset all registers
                sclk_sync <= (others => '0');
                ss_n_sync <= (others => '1');
                sclk_prev <= '0';
                bit_cnt <= (others => '0');
                rx_shift <= (others => '0');
                tx_shift <= (others => '0');
                miso_reg <= '0';
                data_valid_reg <= '0';
                ack_reg <= '0';
                ss_active <= '0';
            else
                -- Synchronize inputs (2-stage for metastability)
                sclk_sync <= sclk_sync(0) & sclk;
                ss_n_sync <= ss_n_sync(0) & ss_n;
                sclk_prev <= sclk_sync(1);
                
                -- Default pulse outputs
                data_valid_reg <= '0';
                ack_reg <= '0';
                
                -- Slave select detection
                ss_active <= not ss_n_sync(1);
                
                if ss_n_sync(1) = '1' then
                    -- Slave not selected - reset state
                    bit_cnt <= (others => '0');
                    rx_shift <= (others => '0');
                    tx_shift <= data_in;
                    miso_reg <= data_in(DATA_WIDTH-1); -- Output MSB immediately
                else
                    -- Slave selected - SPI Mode 0 operation
                    
                    -- SCLK rising edge: sample MOSI
                    if sclk_sync(1) = '1' and sclk_prev = '0' then
                        rx_shift <= rx_shift(DATA_WIDTH-2 downto 0) & mosi;
                        
                        if bit_cnt = to_unsigned(DATA_WIDTH-1, 4) then
                            -- Complete byte received
                            data_out <= rx_shift(DATA_WIDTH-2 downto 0) & mosi;
                            data_valid_reg <= '1';
                            ack_reg <= '1';
                            bit_cnt <= (others => '0');
                            tx_shift <= data_in; -- Load next byte
                            miso_reg <= data_in(DATA_WIDTH-1);
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                    end if;
                    
                    -- SCLK falling edge: update MISO (shift out next bit)
                    if sclk_sync(1) = '0' and sclk_prev = '1' then
                        -- Shift tx_shift left and update MISO with the MSB
                        tx_shift <= tx_shift(DATA_WIDTH-2 downto 0) & '0';
                        miso_reg <= tx_shift(DATA_WIDTH-2);
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Output assignments
    miso       <= miso_reg;
    data_valid <= data_valid_reg;
    ack        <= ack_reg;
end Behavioral;