--------------------------------------------------------------------------------
-- PROJECT: SPI MASTER AND SLAVE FOR FPGA
--------------------------------------------------------------------------------
-- AUTHORS: Jakub Cabal <jakubcabal@gmail.com>
-- LICENSE: The MIT License, please read LICENSE file
-- WEBSITE: https://github.com/jakubcabal/spi-fpga
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

-- THE SPI SLAVE MODULE SUPPORT ONLY SPI MODE 0 (CPOL=0, CPHA=0)!!!

entity SPI_SLAVE is
    Generic (
        WORD_SIZE : natural := 8 -- size of transfer word in bits, must be power of two
    );
    Port (
        CLK      : in  std_logic; -- system clock
        RESET      : in  std_logic; -- high active synchronous reset

        -- SPI SLAVE INTERFACE

        SCLK     : in  std_logic; -- SPI clock
        CS_N     : in  std_logic; -- SPI chip select, active in low
        MOSI     : in  std_logic; -- SPI serial data from master to slave
        MISO     : out std_logic; -- SPI serial data from slave to master

        -- USER INTERFACE

        DATA_IN      : in  std_logic_vector(WORD_SIZE-1 downto 0); -- data for transmission to SPI master
        DATA_IN_VALID  : in  std_logic; -- when DATA_IN_VALID = 1, data for transmission are valid
        DATA_IN_READY  : out std_logic; -- when DATA_IN_READY = 1, SPI slave is ready to accept valid data for transmission
        DATA_OUT     : out std_logic_vector(WORD_SIZE-1 downto 0); -- received data from SPI master
        DATA_OUT_VALID : out std_logic  -- when DATA_OUT_VALID = 1, received data are valid
    );
end entity;

architecture RTL of SPI_SLAVE is

    constant BIT_CNT_WIDTH : natural := natural(ceil(log2(real(WORD_SIZE))));

    signal sclk_meta          : std_logic; -- for metastability
    signal cs_n_meta          : std_logic; -- for metastability
    signal mosi_meta          : std_logic; -- for metastability
    signal sclk_reg           : std_logic;
    signal cs_n_reg           : std_logic;
    signal mosi_reg           : std_logic;
    signal spi_clk_reg        : std_logic;
    signal spi_clk_rising_edge_en   : std_logic;
    signal spi_clk_falling_edge_en   : std_logic;
    signal bit_cnt            : unsigned(BIT_CNT_WIDTH-1 downto 0);
    signal bit_cnt_max        : std_logic;
    signal last_bit_en        : std_logic;
    signal load_data_en       : std_logic;
    signal data_shiftreg         : std_logic_vector(WORD_SIZE-1 downto 0);
    signal slave_ready        : std_logic;
    signal shiftreg_busy         : std_logic;
    signal rx_data_valid        : std_logic;

begin

    -- Synchronization registers to eliminate possible metastability.
    sync_ffs_process : process (CLK)
    begin
        if (rising_edge(CLK)) then
            sclk_meta <= SCLK;
            cs_n_meta <= CS_N;
            mosi_meta <= MOSI;
            sclk_reg  <= sclk_meta;
            cs_n_reg  <= cs_n_meta;
            mosi_reg  <= mosi_meta;
        end if;
    end process;

 

    -- The SPI clock register is necessary for clock edge detection.
    spi_clk_reg_process : process (CLK)
    begin
        if (rising_edge(CLK)) then
            if (RESET = '1') then
                spi_clk_reg <= '0';
            else
                spi_clk_reg <= sclk_reg;
            end if;
        end if;
    end process;


    -- Falling edge is detect when sclk_reg=0 and spi_clk_reg=1.
    spi_clk_falling_edge_en <= not sclk_reg and spi_clk_reg;

    -- Rising edge is detect when sclk_reg=1 and spi_clk_reg=0.
    spi_clk_rising_edge_en <= sclk_reg and not spi_clk_reg;

    -- -------------------------------------------------------------------------
    --  RECEIVED BITS COUNTER
    -- -------------------------------------------------------------------------

    -- The counter counts received bits from the master. Counter is enabled when
    -- falling edge of SPI clock is detected and not asserted cs_n_reg.
    bit_cnt_process : process (CLK)
    begin
        if (rising_edge(CLK)) then
            if (RESET = '1') then
                bit_cnt <= (others => '0');
            elsif (spi_clk_falling_edge_en = '1' and cs_n_reg = '0') then
                if (bit_cnt_max = '1') then
                    bit_cnt <= (others => '0');
                else
                    bit_cnt <= bit_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- The flag of maximal value of the bit counter.
    bit_cnt_max <= '1' when (bit_cnt = WORD_SIZE-1) else '0';

    -- -------------------------------------------------------------------------
    --  LAST BIT FLAG REGISTER
    -- -------------------------------------------------------------------------

    -- The flag of last bit of received byte is only registered the flag of
    -- maximal value of the bit counter.
    last_bit_en_process : process (CLK)
    begin
        if (rising_edge(CLK)) then
            if (RESET = '1') then
                last_bit_en <= '0';
            else
                last_bit_en <= bit_cnt_max;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    --  RECEIVED DATA VALID FLAG
    -- -------------------------------------------------------------------------

    -- Received data from master are valid when falling edge of SPI clock is
    -- detected and the last bit of received byte is detected.
    rx_data_valid <= spi_clk_falling_edge_en and last_bit_en;

    -- -------------------------------------------------------------------------
    --  SHIFT REGISTER BUSY FLAG REGISTER
    -- -------------------------------------------------------------------------

    -- Data shift register is busy until it sends all input data to SPI master.
    shreg_busy_p : process (CLK)
    begin
        if (rising_edge(CLK)) then
            if (RESET = '1') then
                shiftreg_busy <= '0';
            else
                if (DATA_IN_VALID = '1' and (cs_n_reg = '1' or rx_data_valid = '1')) then
                    shiftreg_busy <= '1';
                elsif (rx_data_valid = '1') then
                    shiftreg_busy <= '0';
                else
                    shiftreg_busy <= shiftreg_busy;
                end if;
            end if;
        end if;
    end process;

    -- The SPI slave is ready for accept new input data when cs_n_reg is assert and
    -- shift register not busy or when received data are valid.
    slave_ready <= (cs_n_reg and not shiftreg_busy) or rx_data_valid;
    
    -- The new input data is loaded into the shift register when the SPI slave
    -- is ready and input data are valid.
    load_data_en <= slave_ready and DATA_IN_VALID;

    -- -------------------------------------------------------------------------
    --  DATA SHIFT REGISTER
    -- -------------------------------------------------------------------------

    -- The shift register holds data for sending to master, capture and store
    -- incoming data from master.
    data_shiftreg_process : process (CLK)
    begin
        if (rising_edge(CLK)) then
            if (load_data_en = '1') then
                data_shiftreg <= DATA_IN;
            elsif (spi_clk_rising_edge_en = '1' and cs_n_reg = '0') then
                data_shiftreg <= data_shiftreg(WORD_SIZE-2 downto 0) & mosi_reg;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    --  MISO REGISTER
    -- -------------------------------------------------------------------------

    -- The output MISO register ensures that the bits are transmit to the master
    -- when is not assert cs_n_reg and falling edge of SPI clock is detected.
    miso_process : process (CLK)
    begin
        if (rising_edge(CLK)) then
            if (load_data_en = '1') then
                MISO <= DATA_IN(WORD_SIZE-1);
            elsif (spi_clk_falling_edge_en = '1' and cs_n_reg = '0') then
                MISO <= data_shiftreg(WORD_SIZE-1);
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    --  ASSIGNING OUTPUT SIGNALS
    -- -------------------------------------------------------------------------

    DATA_IN_READY  <= slave_ready;
    DATA_OUT     <= data_shiftreg;
    DATA_OUT_VALID <= rx_data_valid;

end architecture;