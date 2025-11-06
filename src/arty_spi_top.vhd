library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Top-level module for Arty A7-35T board with SPI_SLAVE
entity arty_spi_top is
    port (
        -- Clock input (100 MHz on Arty)
        clk100          : in  std_logic;
        
        -- Reset button (BTN0 on Arty - active high)
        btn_reset       : in  std_logic;
        
        -- Mode switch (sw[0] - CNN simulation mode when high)
        sw              : in  std_logic_vector(3 downto 0);
        
        -- SPI interface on Pmod connector JA
        spi_sclk        : in  std_logic;   -- JA1
        spi_mosi        : in  std_logic;   -- JA2  
        spi_miso        : out std_logic;   -- JA3
        spi_ss_n        : in  std_logic;   -- JA4
        
        -- LEDs to show received data (4 regular LEDs on Arty)
        led             : out std_logic_vector(3 downto 0);
        
        -- Use RGB LEDs to show upper 4 bits and status
        led1_r          : out std_logic;   -- Bit 4 of received data
        led1_g          : out std_logic;   -- Bit 5 of received data
        led1_b          : out std_logic;   -- Bit 6 of received data
        led2_r          : out std_logic;   -- Bit 7 of received data (MSB)
        led2_g          : out std_logic;   -- Ready to receive (green)
        led2_b          : out std_logic;   -- Data valid indicator
        
        -- RGB LED0 - Status
        led0_r          : out std_logic;   -- RX valid blink
        led0_g          : out std_logic;   -- TX ready
        led0_b          : out std_logic    -- TX active / CNN processing
    );
end arty_spi_top;

architecture Behavioral of arty_spi_top is
    
    -- CNN simulation constants
    constant CNN_INPUT_SIZE : natural := 784;  -- 28x28 pixels
    constant CNN_DELAY_CYCLES : natural := 200000;  -- 2ms at 100 MHz
    
    -- FSM states for CNN simulation mode
    type cnn_state_t is (IDLE, COLLECTING, PROCESSING, SENDING_RESULT);
    signal cnn_state : cnn_state_t := IDLE;
    
    -- Internal signals for SPI_SLAVE
    signal rst          : std_logic; -- Active-high reset
    signal tx_data      : std_logic_vector(7 downto 0);
    signal tx_valid     : std_logic;
    signal tx_ready     : std_logic;
    signal rx_data      : std_logic_vector(7 downto 0);
    signal rx_valid     : std_logic;
    
    -- Data register to hold received values
    signal received_data : std_logic_vector(7 downto 0) := x"00";
    
    -- Counter for auto-transmit (echo mode)
    signal tx_counter    : unsigned(7 downto 0) := (others => '0');
    
    -- Blink counter for RX indicator
    signal rx_blink_cnt  : unsigned(23 downto 0) := (others => '0');
    
    -- CNN simulation signals
    signal cnn_mode         : std_logic;  -- sw(0) - enable CNN simulation
    signal pixel_count      : unsigned(9 downto 0) := (others => '0');  -- 0 to 783
    signal delay_counter    : unsigned(17 downto 0) := (others => '0');  -- 0 to 199999
    signal cnn_result       : unsigned(3 downto 0) := (others => '0');   -- Dummy result 0-9
    signal result_sent      : std_logic := '0';
    signal status_byte      : std_logic_vector(7 downto 0);  -- Status encoding
    
begin
    -- Button is active-high on input, module needs active-high reset
    rst <= btn_reset;
    
    -- CNN simulation mode controlled by switch 0
    cnn_mode <= sw(0);
    
    -- Instantiate SPI_SLAVE module
    spi_slave_inst : entity work.SPI_SLAVE
        generic map (
            WORD_SIZE => 8
        )
        port map (
            CLK            => clk100,
            RESET          => rst,
            -- SPI Interface
            SCLK           => spi_sclk,
            CS_N           => spi_ss_n,
            MOSI           => spi_mosi,
            MISO           => spi_miso,
            -- User Interface
            DATA_IN        => tx_data,
            DATA_IN_VALID  => tx_valid,
            DATA_IN_READY  => tx_ready,
            DATA_OUT       => rx_data,
            DATA_OUT_VALID => rx_valid
        );
    
    -- =========================================================================
    -- CNN Simulation FSM
    -- =========================================================================
    cnn_fsm_proc : process(clk100)
    begin
        if rising_edge(clk100) then
            if rst = '1' then
                cnn_state <= IDLE;
                pixel_count <= (others => '0');
                delay_counter <= (others => '0');
                cnn_result <= (others => '0');
                result_sent <= '0';
            else
                case cnn_state is
                    when IDLE =>
                        pixel_count <= (others => '0');
                        delay_counter <= (others => '0');
                        result_sent <= '0';
                        cnn_result <= (others => '0');
                        
                        -- If in CNN mode and receive first pixel, start collecting
                        if cnn_mode = '1' and rx_valid = '1' then
                            cnn_state <= COLLECTING;
                            pixel_count <= to_unsigned(1, 10);  -- Count first pixel as 1
                            -- Accumulate first pixel into result
                            cnn_result <= cnn_result + unsigned(rx_data(3 downto 0));
                        end if;
                    
                    when COLLECTING =>
                        -- Collect incoming pixels and accumulate for dummy result
                        if rx_valid = '1' then
                            -- Accumulate all received pixels
                            cnn_result <= cnn_result + unsigned(rx_data(3 downto 0));
                            
                            if pixel_count = CNN_INPUT_SIZE - 1 then
                                -- Received all 784 pixels, start processing
                                cnn_state <= PROCESSING;
                                pixel_count <= (others => '0');
                                delay_counter <= (others => '0');
                            else
                                pixel_count <= pixel_count + 1;
                            end if;
                        end if;
                    
                    when PROCESSING =>
                        -- Wait for 2ms (CNN computation simulation)
                        if delay_counter = CNN_DELAY_CYCLES - 1 then
                            cnn_state <= SENDING_RESULT;
                            delay_counter <= (others => '0');
                        else
                            delay_counter <= delay_counter + 1;
                        end if;
                    
                    when SENDING_RESULT =>
                        -- Wait for result to be sent via SPI
                        if tx_ready = '1' and tx_valid = '1' then
                            result_sent <= '1';
                        end if;
                        
                        if result_sent = '1' then
                            cnn_state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    -- =========================================================================
    -- TX Data Control - Either echo mode or CNN result mode
    -- =========================================================================
    tx_data_proc : process(clk100)
    begin
        if rising_edge(clk100) then
            if rst = '1' then
                tx_counter <= (others => '0');
                tx_valid <= '0';
            else
                -- Default: deassert valid after one cycle
                if tx_valid = '1' then
                    tx_valid <= '0';
                end if;
                
                -- CNN mode behavior depends on state
                if cnn_mode = '1' then
                    case cnn_state is
                        when IDLE | COLLECTING | PROCESSING =>
                            -- During collection and processing: send status byte
                            if tx_ready = '1' and tx_valid = '0' then
                                tx_valid <= '1';
                            end if;
                            
                        when SENDING_RESULT =>
                            -- Only in result state: send actual result
                            if tx_ready = '1' and tx_valid = '0' and result_sent = '0' then
                                tx_valid <= '1';
                            end if;
                    end case;
                -- Echo mode: auto-increment counter (only when CNN mode is OFF)
                else
                    if tx_ready = '1' and tx_valid = '0' then
                        tx_counter <= tx_counter + 1;
                        tx_valid <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Mux TX data: CNN result, status during collection, or echo counter
    -- Status byte encoding (CNN mode):
    -- Bits [7:4] = State: 0x0=IDLE, 0x1=COLLECTING, 0x2=PROCESSING, 0x8=RESULT_READY
    -- Bits [3:0] = Progress/Result
    with cnn_state select status_byte <=
        x"00" when IDLE,                                      -- 0x00 = Idle
        x"1" & std_logic_vector(pixel_count(9 downto 6)) when COLLECTING,  -- 0x1X = Collecting (X shows progress)
        x"20" when PROCESSING,                                -- 0x20 = Processing
        x"8" & std_logic_vector(cnn_result) when SENDING_RESULT;  -- 0x8X = Result ready (X is result)
    
    tx_data <= x"8" & std_logic_vector(cnn_result) when (cnn_mode = '1' and cnn_state = SENDING_RESULT) 
               else status_byte when (cnn_mode = '1')  -- Status byte during other states
               else std_logic_vector(tx_counter);
    
    -- Latch received data and display on LEDs
    rx_data_proc : process(clk100)
    begin
        if rising_edge(clk100) then
            if rst = '1' then
                received_data <= (others => '0');
                rx_blink_cnt <= (others => '0');
            else
                -- Latch new received data
                if rx_valid = '1' then
                    received_data <= rx_data;
                    rx_blink_cnt <= (others => '1'); -- Start blink timer
                elsif rx_blink_cnt > 0 then
                    rx_blink_cnt <= rx_blink_cnt - 1;
                end if;
            end if;
        end if;
    end process;
    
    -- Display all 8 bits of received data across LEDs
    led      <= received_data(3 downto 0);  -- Lower 4 bits on regular LEDs
    led1_r   <= received_data(4);           -- Bit 4
    led1_g   <= received_data(5);           -- Bit 5  
    led1_b   <= received_data(6);           -- Bit 6
    led2_r   <= received_data(7);           -- Bit 7 (MSB)
    
    -- Status indicators
    led0_r   <= '1' when (rx_blink_cnt > 0) else '0';  -- RX blink
    led0_g   <= cnn_mode when (cnn_mode = '1') else tx_ready;  -- CNN mode indicator (green) / TX ready in echo mode
    led0_b   <= '1' when (cnn_state = PROCESSING) else '0';  -- Processing indicator (blue)
    led2_g   <= '1' when (cnn_state = COLLECTING) else '0';  -- Collecting pixels (green)
    led2_b   <= '1' when (cnn_state = SENDING_RESULT) else '0';  -- Result ready! (blue blink)
    
end Behavioral;