library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Top-level module for Arty A7-35T board
entity arty_spi_top is
    port (
        -- Clock input (100 MHz on Arty)
        clk100          : in  std_logic;
        
        -- Reset button (BTN0 on Arty - active high, we'll invert it)
        btn_reset       : in  std_logic;
        
        -- SPI interface on Pmod connector (you can choose JA, JB, JC, or JD)
        -- Using JA connector as example:
        spi_sclk        : in  std_logic;   -- JA1
        spi_mosi        : in  std_logic;   -- JA2  
        spi_miso        : out std_logic;   -- JA3
        spi_ss_n        : in  std_logic;   -- JA4
        
        -- LEDs 0-7 to show 8-bit pixel value received from MOSI (LED0=bit7, LED7=bit0)
        led0            : out std_logic;   -- Bit 7 (MSB)
        led1            : out std_logic;   -- Bit 6
        led2            : out std_logic;   -- Bit 5
        led3            : out std_logic;   -- Bit 4
        led4            : out std_logic;   -- Bit 3
        led5            : out std_logic;   -- Bit 2
        led6            : out std_logic;   -- Bit 1
        led7            : out std_logic    -- Bit 0 (LSB)
    );
end arty_spi_top;

architecture Behavioral of arty_spi_top is
    -- Component declaration for SPI slave
    component SPI_SLAVE is
        generic (
            WORD_SIZE : natural := 8
        );
        port (
            CLK             : in  std_logic;
            RESET           : in  std_logic;
            SCLK            : in  std_logic;
            CS_N            : in  std_logic;
            MOSI            : in  std_logic;
            MISO            : out std_logic;
            DATA_IN         : in  std_logic_vector(7 downto 0);
            DATA_IN_VALID   : in  std_logic;
            DATA_IN_READY   : out std_logic;
            DATA_OUT        : out std_logic_vector(7 downto 0);
            DATA_OUT_VALID  : out std_logic
        );
    end component;
    
    -- Internal signals
    signal reset_active     : std_logic;
    signal spi_data_out     : std_logic_vector(7 downto 0);
    signal spi_data_in      : std_logic_vector(7 downto 0);
    signal spi_data_in_valid: std_logic;
    signal spi_data_in_ready: std_logic;
    signal data_out_valid   : std_logic;
    
    -- Pixel value register to hold received data
    signal pixel_value : std_logic_vector(7 downto 0) := x"00";
    
begin
    -- Reset is active high for new SPI module
    reset_active <= btn_reset;
    
    -- Send back the inverse of received pixel value
    spi_data_in <= not pixel_value;
    spi_data_in_valid <= '1';  -- Always ready to send data
    
    -- Display real-time SPI shift register on LEDs 0-7 (LED0=bit7, LED7=bit0)
    -- This shows bits shifting in real-time as they are received
    led0 <= spi_data_out(7);  -- MSB - shows current shift register bit 7
    led1 <= spi_data_out(6);  -- Shows current shift register bit 6
    led2 <= spi_data_out(5);  -- Shows current shift register bit 5
    led3 <= spi_data_out(4);  -- Shows current shift register bit 4
    led4 <= spi_data_out(3);  -- Shows current shift register bit 3
    led5 <= spi_data_out(2);  -- Shows current shift register bit 2
    led6 <= spi_data_out(1);  -- Shows current shift register bit 1
    led7 <= spi_data_out(0);  -- LSB - shows current shift register bit 0
    
    -- Instantiate SPI slave
    spi_slave_inst: SPI_SLAVE
        generic map (
            WORD_SIZE => 8
        )
        port map (
            CLK             => clk100,
            RESET           => reset_active,
            SCLK            => spi_sclk,
            CS_N            => spi_ss_n,
            MOSI            => spi_mosi,
            MISO            => spi_miso,
            DATA_IN         => spi_data_in,
            DATA_IN_VALID   => spi_data_in_valid,
            DATA_IN_READY   => spi_data_in_ready,
            DATA_OUT        => spi_data_out,
            DATA_OUT_VALID  => data_out_valid
        );
    
    -- Process to store completed pixel values (for reference, though LEDs show real-time data)
    process(clk100)
    begin
        if rising_edge(clk100) then
            if reset_active = '1' then
                pixel_value <= x"00";  -- Clear stored value
            elsif data_out_valid = '1' then
                pixel_value <= spi_data_out;  -- Store completed 8-bit word
            end if;
        end if;
    end process;
    
end Behavioral;