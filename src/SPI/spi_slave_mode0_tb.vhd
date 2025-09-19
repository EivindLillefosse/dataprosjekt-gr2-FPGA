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
    constant DATA_LENGTH : integer := 8;
    signal data_in  : std_logic_vector(DATA_LENGTH-1 downto 0) := (others => '0');
    signal data_out : std_logic_vector(DATA_LENGTH-1 downto 0);
    signal data_valid : std_logic;
    signal ack     : std_logic;

    type data_array is array (natural range <>) of std_logic_vector(DATA_LENGTH-1 downto 0);
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

    -- DUT instantiation
    dut: entity work.spi_slave_mode0
        generic map (
            DATA_LENGTH => DATA_LENGTH
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
    begin
        rst_n <= '0';
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait for 2*CLK_PERIOD;

        for i in TX_DATA'range loop
            data_in <= RX_DATA(i); -- what slave will send back
            ss_n <= '0';
            for bit in DATA_LENGTH-1 downto 0 loop
                mosi <= TX_DATA(i)(bit);
                wait for SPI_PERIOD/4;
                sclk <= '1';
                wait for SPI_PERIOD/2;
                sclk <= '0';
                wait for SPI_PERIOD/4;
            end loop;
            ss_n <= '1';
            wait for SPI_PERIOD;
            
            
        end loop;

        wait for 10*CLK_PERIOD;
        report "Testbench finished." severity note;
        wait for 10 ms;
        std.env.stop;
    end process;

end architecture sim;
