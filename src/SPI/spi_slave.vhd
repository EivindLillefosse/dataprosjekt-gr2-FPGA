library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_slave is
    generic (
        DATA_WIDTH : integer := 8  -- Default to 8-bit data width
    );
    port (
        -- System signals
        clk         : in  std_logic;                                    -- FPGA system clock
        rst_n       : in  std_logic;                                    -- Active low reset
        
        -- SPI interface signals
        spi_sclk    : in  std_logic;                                    -- Serial clock from master
        spi_cs_n    : in  std_logic;                                    -- Chip select (active low)
        spi_mosi    : in  std_logic;                                    -- Master out, slave in
        spi_miso    : out std_logic;                                    -- Master in, slave out
        
        -- Data interface
        data_in     : in  std_logic_vector(DATA_WIDTH-1 downto 0);     -- Data to be sent to master
        data_out    : out std_logic_vector(DATA_WIDTH-1 downto 0);     -- Data received from master
        data_valid  : out std_logic;                                    -- Indicates new data received
        busy        : out std_logic                                     -- Indicates transmission in progress
    );
end entity spi_slave;

architecture rtl of spi_slave is
    -- Internal signals
    signal sclk_prev    : std_logic;                                   -- Previous clock state for edge detection
    signal bit_counter  : integer range 0 to DATA_WIDTH-1;             -- Counts bits during transfer
    signal shift_reg_in : std_logic_vector(DATA_WIDTH-1 downto 0);     -- Shift register for receiving
    signal shift_reg_out: std_logic_vector(DATA_WIDTH-1 downto 0);     -- Shift register for transmitting
    signal transfer_active : std_logic;                                -- Indicates active transfer
    
begin
    -- Main process for SPI communication
    process(clk)
    begin
        if rising_edge(clk) then
            -- Asynchronous reset
            if rst_n = '0' then
                shift_reg_in  <= (others => '0');
                shift_reg_out <= (others => '0');
                bit_counter   <= DATA_WIDTH-1;
                sclk_prev    <= '0';
                data_valid   <= '0';
                busy         <= '0';
                transfer_active <= '0';
                spi_miso     <= '0';
                
            else
                -- Default state for data_valid
                data_valid <= '0';
                
                -- Detect start of new transfer
                if spi_cs_n = '1' then
                    transfer_active <= '0';
                    bit_counter <= DATA_WIDTH-1;
                    busy <= '0';
                elsif spi_cs_n = '0' and transfer_active = '0' then
                    transfer_active <= '1';
                    shift_reg_out <= data_in;  -- Load new data to send
                    busy <= '1';
                end if;
                
                -- Store previous clock state
                sclk_prev <= spi_sclk;
                
                -- Only process during active transfer
                if transfer_active = '1' then
                    -- Sample MOSI on rising edge of SCLK
                    if spi_sclk = '1' and sclk_prev = '0' then
                        shift_reg_in <= shift_reg_in(DATA_WIDTH-2 downto 0) & spi_mosi;
                    end if;
                    
                    -- Update MISO on falling edge of SCLK
                    if spi_sclk = '0' and sclk_prev = '1' then
                        if bit_counter = 0 then
                            -- End of transfer
                            data_valid <= '1';
                            data_out <= shift_reg_in;
                            bit_counter <= DATA_WIDTH-1;
                            -- Load next data to send
                            shift_reg_out <= data_in;
                        else
                            bit_counter <= bit_counter - 1;
                        end if;
                        -- Shift out next bit
                        spi_miso <= shift_reg_out(bit_counter);
                    end if;
                end if;
            end if;
        end if;
    end process;
    
end architecture rtl;