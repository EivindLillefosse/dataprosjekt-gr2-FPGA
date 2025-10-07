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
        
        -- LEDs to show received data (4 regular LEDs on Arty)
        led             : out std_logic_vector(3 downto 0);
        
        -- Use RGB LEDs to show upper 4 bits and ACK
        led1_r          : out std_logic;   -- Bit 4 of received data
        led1_g          : out std_logic;   -- Bit 5 of received data
        led1_b          : out std_logic;   -- Bit 6 of received data
        led2_r          : out std_logic;   -- Bit 7 of received data (MSB)
        led2_g          : out std_logic;   -- ACK signal when byte received
        led2_b          : out std_logic;   -- Unused
        
        -- RGB LEDs to show status
        led0_r          : out std_logic;   -- Red when data received
        led0_g          : out std_logic;   -- Green when idle
        led0_b          : out std_logic    -- Blue unused
    );
end arty_spi_top;

architecture Behavioral of arty_spi_top is
    -- Component declaration for our simple SPI slave
    component spi_slave_simple is
        port (
            clk         : in  std_logic;
            rst_n       : in  std_logic;
            sclk        : in  std_logic;
            mosi        : in  std_logic;
            miso        : out std_logic;
            ss_n        : in  std_logic;
            data_in     : in  std_logic_vector(7 downto 0);
            data_out    : out std_logic_vector(7 downto 0);
            data_ready  : out std_logic;
            byte_ack    : out std_logic
        );
    end component;
    
    -- Internal signals
    signal rst_n        : std_logic;
    signal spi_data_out : std_logic_vector(7 downto 0);
    signal spi_data_in  : std_logic_vector(7 downto 0);
    signal data_ready   : std_logic;
    signal byte_ack     : std_logic;
    
    -- Data register to hold received values
    signal received_data : std_logic_vector(7 downto 0) := x"AA";
    
begin
    -- Invert reset button (button is active high, SPI slave needs active low reset)
    rst_n <= not btn_reset;
    
    -- For demo: send back the inverse of what we received
    spi_data_in <= not received_data;
    
    -- Show all 8 bits of received data across multiple LEDs
    led <= received_data(3 downto 0);     -- Lower 4 bits on regular LEDs
    
    -- Upper 4 bits on RGB LEDs
    led1_r <= received_data(4);           -- Bit 4
    led1_g <= received_data(5);           -- Bit 5  
    led1_b <= received_data(6);           -- Bit 6
    led2_r <= received_data(7);           -- Bit 7 (MSB)
    
    -- Status indication
    led0_r <= data_ready;                 -- Red flash when data received
    led0_g <= not data_ready;             -- Green when idle
    led0_b <= '0';                        -- Blue unused
    
    -- ACK indication
    led2_b <= byte_ack;                   -- Green flash when complete byte ACK
    led2_g <= '0';                        -- Blue unused
    
    -- Instantiate SPI slave
    spi_slave_inst: spi_slave_simple
        port map (
            clk         => clk100,
            rst_n       => rst_n,
            sclk        => spi_sclk,
            mosi        => spi_mosi,
            miso        => spi_miso,
            ss_n        => spi_ss_n,
            data_in     => spi_data_in,
            data_out    => spi_data_out,
            data_ready  => data_ready,
            byte_ack    => byte_ack
        );
    
    -- Process to store received data
    process(clk100)
    begin
        if rising_edge(clk100) then
            if rst_n = '0' then
                received_data <= x"AA";  -- Default pattern
            elsif data_ready = '1' then
                received_data <= spi_data_out;  -- Store new received data
            end if;
        end if;
    end process;
    
end Behavioral;