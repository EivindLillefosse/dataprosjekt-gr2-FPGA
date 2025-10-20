library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_slave_simple_tb is
end spi_slave_simple_tb;

architecture Behavioral of spi_slave_simple_tb is
    -- Component declaration
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
            data_ready  : out std_logic
        );
    end component;
    
    -- Test signals
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sclk : std_logic := '0';
    signal mosi : std_logic := '0';
    signal miso : std_logic;
    signal ss_n : std_logic := '1';
    signal data_in : std_logic_vector(7 downto 0) := x"AA";  -- Default test data
    signal data_out : std_logic_vector(7 downto 0);
    signal data_ready : std_logic;
    
    -- Test control
    signal test_done : boolean := false;
    
    -- Clock periods
    constant CLK_PERIOD : time := 10 ns;   -- 100 MHz system clock
    constant SCLK_PERIOD : time := 200 ns; -- Much slower SPI clock for easy viewing
    
begin
    -- Instantiate the Unit Under Test (UUT)
    uut: spi_slave_simple
        port map (
            clk => clk,
            rst_n => rst_n,
            sclk => sclk,
            mosi => mosi,
            miso => miso,
            ss_n => ss_n,
            data_in => data_in,
            data_out => data_out,
            data_ready => data_ready
        );
    
    -- System clock generation
    clk_process: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;
    
    -- Test process
    test_process: process
        -- Procedure to send one byte via SPI
        procedure send_spi_byte(data_byte: std_logic_vector(7 downto 0)) is
        begin
            -- Select slave
            ss_n <= '0';
            wait for SCLK_PERIOD;
            
            -- Send 8 bits (MSB first)
            for i in 7 downto 0 loop
                mosi <= data_byte(i);
                
                -- Rising edge: slave samples our data
                sclk <= '1';
                wait for SCLK_PERIOD/2;
                
                -- Falling edge: slave updates MISO
                sclk <= '0';
                wait for SCLK_PERIOD/2;
            end loop;
            
            -- Deselect slave
            ss_n <= '1';
            wait for SCLK_PERIOD;
        end procedure;
        
    begin
        -- Initial setup
        ss_n <= '1';
        sclk <= '0';  -- Mode 0: SCLK idles low
        mosi <= '0';
        
        -- Reset the system
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 100 ns;
        
        -- Test 1: Send 0x55 to slave, expect to receive 0xAA back
        data_in <= x"AA";  -- Slave will send this back
        send_spi_byte(x"55");
        
        -- Check results
        wait for 50 ns;
        assert data_out = x"55" severity error;
        assert data_ready = '1' report "Error: At " & integer'image(now / 1 ns) & " ns: data_ready should be '1', but got '0'" severity error;
        
        wait for 200 ns;
        
        -- Test 2: Send 0xCC to slave, expect to receive 0x33 back  
        data_in <= x"33";  -- Slave will send this back
        send_spi_byte(x"CC");
        
        -- Check results
        wait for 50 ns;
        assert data_out = x"CC" report "Error: At " & integer'image(now / 1 ns) & " ns: Expected data_out = 0xCC, but got 0x" & 
                                        to_hstring(unsigned(data_out)) severity error;
        
        wait for 200 ns;
        
        -- Test 3: Send alternating pattern
        data_in <= x"F0";
        send_spi_byte(x"0F");
        
        wait for 50 ns;
        assert data_out = x"0F" report "Error: At " & integer'image(now / 1 ns) & " ns: Expected data_out = 0x0F, but got 0x" & 
                                        to_hstring(unsigned(data_out)) severity error;
        
        -- End simulation
        test_done <= true;
        wait;
    end process;
    
end Behavioral;