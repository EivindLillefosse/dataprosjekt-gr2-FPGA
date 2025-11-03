--------------------------------------------------------------------------------
-- Top-level wrapper for SPI_SLAVE module
-- Connects internal DATA_IN/DATA_OUT to loopback logic and LEDs for testing
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity SPI_SLAVE_TOP is
    Generic (
        WORD_SIZE : natural := 8
    );
    Port (
        -- System Interface
        CLK      : in  std_logic;
        RESET    : in  std_logic;
        
        -- SPI Interface (connect to external pins)
        SCLK     : in  std_logic;
        CS_N     : in  std_logic;
        MOSI     : in  std_logic;
        MISO     : out std_logic;
        
        -- Debug outputs (optional - connect to LEDs)
        LED      : out std_logic_vector(3 downto 0);
        LED0_R   : out std_logic;
        LED0_G   : out std_logic;
        LED0_B   : out std_logic
    );
end entity;

architecture RTL of SPI_SLAVE_TOP is

    signal data_in       : std_logic_vector(WORD_SIZE-1 downto 0);
    signal data_in_valid : std_logic;
    signal data_in_ready : std_logic;
    signal data_out      : std_logic_vector(WORD_SIZE-1 downto 0);
    signal data_out_valid: std_logic;
    
    -- Loopback register: stores received data and sends it back
    signal loopback_reg  : std_logic_vector(WORD_SIZE-1 downto 0) := (others => '0');
    signal received_count: unsigned(3 downto 0) := (others => '0');

begin

    -- Instantiate SPI_SLAVE
    spi_slave_inst : entity work.SPI_SLAVE
    generic map (
        WORD_SIZE => WORD_SIZE
    )
    port map (
        CLK            => CLK,
        RESET          => RESET,
        SCLK           => SCLK,
        CS_N           => CS_N,
        MOSI           => MOSI,
        MISO           => MISO,
        DATA_IN        => data_in,
        DATA_IN_VALID  => data_in_valid,
        DATA_IN_READY  => data_in_ready,
        DATA_OUT       => data_out,
        DATA_OUT_VALID => data_out_valid
    );

    -- Simple loopback logic: echo received data back to master
    loopback_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                loopback_reg <= (others => '0');
                data_in_valid <= '0';
                received_count <= (others => '0');
            else
                -- Default: no data to send
                data_in_valid <= '0';
                
                -- When data is received, store it and prepare to echo it back
                if data_out_valid = '1' then
                    loopback_reg <= data_out;
                    data_in_valid <= '1';  -- Immediately ready to send it back
                    received_count <= received_count + 1;
                end if;
            end if;
        end if;
    end process;
    
    -- Connect loopback register to DATA_IN
    data_in <= loopback_reg;
    
    -- Drive LEDs with received data for visual feedback
    LED <= std_logic_vector(received_count);
    
    -- RGB LED shows activity
    LED0_R <= not CS_N;              -- Red when chip selected
    LED0_G <= data_out_valid;        -- Green pulse when data received
    LED0_B <= data_in_ready;         -- Blue when ready to accept data

end architecture;
