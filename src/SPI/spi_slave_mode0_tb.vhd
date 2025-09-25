library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_slave_mode0_tb is
end spi_slave_mode0_tb;

architecture sim of spi_slave_mode0_tb is
    constant CLK_PERIOD : time := 5 ns;
    constant SPI_PERIOD : time := 50 ns;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal sclk     : std_logic := '0';
    signal mosi     : std_logic := '0';
    signal miso     : std_logic;
    signal ss_n     : std_logic := '1';
    constant DATA_WIDTH : integer := 8;
    signal data_in  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal data_out : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal data_valid : std_logic;
    signal ack     : std_logic;

    type data_array is array (natural range <>) of std_logic_vector(DATA_WIDTH-1 downto 0);
    constant TX_DATA : data_array := (
        x"A5", x"5A", x"FF", x"00", x"3C"
    );
    constant RX_DATA : data_array := (
        x"1A", x"2B", x"3C", x"4D", x"5E"
    );

begin
    -- Clock generation
    clk_proc: process
    begin
        while true loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
    end process;

    -- Monitor data_valid and ack signals
    monitor_proc: process(clk)
    begin
        if rising_edge(clk) then
            if data_valid = '1' then
                assert false report "DATA_VALID pulse detected" severity note;
            end if;
            if ack = '1' then
                assert false report "ACK pulse detected" severity note;
            end if;
        end if;
    end process;

    -- DUT instantiation
    dut: entity work.spi_slave_mode0
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            sclk     => sclk,
            mosi     => mosi,
            miso     => miso,
            ss_n     => ss_n,
            data_in  => data_in,
            data_out => data_out,
            data_valid => data_valid,
            ack      => ack
        );

    -- SPI Master stimulus: send and receive multiple bytes
    stim_proc: process
        variable received_miso : std_logic_vector(DATA_WIDTH-1 downto 0);
    begin
        -- Initial reset
        rst_n <= '0';
        ss_n <= '1';
        sclk <= '0';
        mosi <= '0';
        wait for 10*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;
        
        assert false report "=== Starting SPI Slave Test ===" severity note;

        for i in TX_DATA'range loop
            -- Prepare data for slave to transmit
            data_in <= RX_DATA(i);
            wait for 2*CLK_PERIOD; -- Allow time for data_in to propagate
            
            assert false report "Starting test iteration" severity note;
            
            -- Assert slave select
            ss_n <= '0';
            wait for CLK_PERIOD;
            
            -- Send byte bit by bit (MSB first)
            received_miso := (others => '0');
            for bit in DATA_WIDTH-1 downto 0 loop
                -- Setup MOSI data
                mosi <= TX_DATA(i)(bit);
                wait for SPI_PERIOD/4;
                
                -- Rising edge - slave samples MOSI
                sclk <= '1';
                wait for SPI_PERIOD/4;
                
                -- Sample MISO in the middle of high period
                received_miso(bit) := miso;
                wait for SPI_PERIOD/4;
                
                -- Falling edge - slave updates MISO
                sclk <= '0';
                wait for SPI_PERIOD/4;
            end loop;
            
            -- Deassert slave select
            ss_n <= '1';
            wait for 2*CLK_PERIOD;
            
            -- Check received data after a few clock cycles
            wait for 3*CLK_PERIOD;
            
            -- Verify received data
            if data_out = TX_DATA(i) then
                assert false report "PASS: Correctly received data" severity note;
            else
                assert false report "FAIL: Received data mismatch" severity error;
            end if;
            
            -- Verify MISO data
            if received_miso = RX_DATA(i) then
                assert false report "PASS: Correctly transmitted data" severity note;
            else
                assert false report "FAIL: Transmitted data mismatch" severity error;
            end if;
            
            -- Verify control signals
            if data_valid = '0' and ack = '0' then
                assert false report "PASS: Control signals OK" severity note;
            else
                assert false report "FAIL: Control signals error" severity error;
            end if;
            
            wait for 5*CLK_PERIOD;
        end loop;

        -- Test reset during transaction
        assert false report "=== Testing Reset During Transaction ===" severity note;
        data_in <= x"AA";
        wait for CLK_PERIOD;
        ss_n <= '0';
        
        -- Send partial byte then reset
        for bit in DATA_WIDTH-1 downto DATA_WIDTH-3 loop
            mosi <= '1';
            wait for SPI_PERIOD/4;
            sclk <= '1';
            wait for SPI_PERIOD/2;
            sclk <= '0';
            wait for SPI_PERIOD/4;
        end loop;
        
        -- Apply reset
        rst_n <= '0';
        wait for 3*CLK_PERIOD;
        rst_n <= '1';
        ss_n <= '1';
        wait for 5*CLK_PERIOD;
        
        assert false report "=== SPI Slave Test Completed ===" severity note;
        wait for 10*CLK_PERIOD;
        wait;
    end process;

end architecture sim;
