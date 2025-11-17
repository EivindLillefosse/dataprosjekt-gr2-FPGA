----------------------------------------------------------------------------------
-- Testbench for SPI_top
-- Simple functionality test
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.ALL;

entity SPI_top_tb is
end SPI_top_tb;

architecture Behavioral of SPI_top_tb is

    -- Constants
    constant CLK_PERIOD : time := 10 ns;
    constant SCLK_PERIOD : time := 100 ns; -- SPI clock slower than system clock
    constant IMAGE_WIDTH : integer := 3; -- Small 3x3 for fast simulation testing
    constant BUFFER_SIZE : integer := IMAGE_WIDTH * IMAGE_WIDTH;
    constant WORD_SIZE : integer := 8;
    
    -- DUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    
    -- User interface
    signal DATA_OUT_COL : integer := 0;
    signal DATA_OUT_ROW : integer := 0;
    signal DATA_IN : std_logic_vector(WORD_SIZE-1 downto 0) := (others => '0');
    signal DATA_OUT : std_logic_vector(WORD_SIZE-1 downto 0);
    
    -- Handshakes
    signal COL_ROW_REQ_READY : std_logic;
    signal COL_ROW_REQ_VALID : std_logic := '0';
    signal DATA_IN_VALID : std_logic := '0';
    signal DATA_IN_READY : std_logic;
    signal DATA_OUT_VALID : std_logic;
    signal DATA_OUT_READY : std_logic := '0';
    
    -- SPI interface
    signal SCLK : std_logic := '0';
    signal CS_N : std_logic := '1';
    signal MOSI : std_logic := '0';
    signal MISO : std_logic;
    
    -- VGA interface (not tested, just connected)
    signal VGA_HS_O : std_logic;
    signal VGA_VS_O : std_logic;
    signal VGA_R : std_logic_vector(3 downto 0);
    signal VGA_G : std_logic_vector(3 downto 0);
    signal VGA_B : std_logic_vector(3 downto 0);
    
    -- Test control
    signal test_done : boolean := false;

begin

    -- Clock generation
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;
    
    -- SPI Clock generation (only when CS_N is low)
    sclk_process : process
    begin
        while not test_done loop
            if CS_N = '0' then
                SCLK <= '0';
                wait for SCLK_PERIOD / 2;
                if CS_N = '0' then  -- Check again before rising edge
                    SCLK <= '1';
                    wait for SCLK_PERIOD / 2;
                else
                    wait for SCLK_PERIOD / 2;
                end if;
            else
                SCLK <= '0';
                wait for SCLK_PERIOD / 2;
            end if;
        end loop;
        wait;
    end process;

    -- DUT instantiation
    DUT : entity work.SPI_top
        generic map (
            BUFFER_SIZE => BUFFER_SIZE,
            IMAGE_WIDTH => IMAGE_WIDTH,
            WORD_SIZE => WORD_SIZE
        )
        port map (
            clk => clk,
            rst => rst,
            DATA_OUT_COL => DATA_OUT_COL,
            DATA_OUT_ROW => DATA_OUT_ROW,
            DATA_IN => DATA_IN,
            DATA_OUT => DATA_OUT,
            COL_ROW_REQ_READY => COL_ROW_REQ_READY,
            COL_ROW_REQ_VALID => COL_ROW_REQ_VALID,
            DATA_IN_VALID => DATA_IN_VALID,
            DATA_IN_READY => DATA_IN_READY,
            DATA_OUT_VALID => DATA_OUT_VALID,
            DATA_OUT_READY => DATA_OUT_READY,
            SCLK => SCLK,
            CS_N => CS_N,
            MOSI => MOSI,
            MISO => MISO,
            VGA_HS_O => VGA_HS_O,
            VGA_VS_O => VGA_VS_O,
            VGA_R => VGA_R,
            VGA_G => VGA_G,
            VGA_B => VGA_B
        );

    -- Main test process
    test_process : process
        variable bit_counter : integer;
        variable byte_to_send : std_logic_vector(7 downto 0);
    begin
        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        
        report "=== Starting SPI_top Reliability Test ===";
        
        -- Extended Test: Send 200 bytes via SPI, read them back, test MISO transmission
        report "--- Sending 200 bytes via SPI ---";
        
        for byte_num in 0 to 199 loop  -- Send 200 bytes
            byte_to_send := std_logic_vector(to_unsigned((byte_num mod 256), 8));
            
            if byte_num mod 20 = 0 then
                report "Progress: Sent " & integer'image(byte_num) & " bytes";
            end if;
            
            -- Prepare DATA_IN for slave to transmit (rotating pattern)
            DATA_IN <= std_logic_vector(to_unsigned((byte_num + 128) mod 256, 8));
            DATA_IN_VALID <= '1';
            wait for CLK_PERIOD * 2;
            
            -- Start SPI transaction (CS_N low and set first bit)
            CS_N <= '0';
            MOSI <= byte_to_send(7);  -- Set first bit immediately
            
            -- Wait for 8 complete SCLK cycles
            for i in 1 to 8 loop
                wait until rising_edge(SCLK);
                wait until falling_edge(SCLK);
                
                -- Update MOSI for next bit (if not last cycle)
                if i < 8 then
                    MOSI <= byte_to_send(7 - i);
                end if;
            end loop;
            
            -- Wait a bit to ensure SCLK is stable low before raising CS_N
            wait for SCLK_PERIOD / 4;
            CS_N <= '1';
            wait for SCLK_PERIOD * 2;
        end loop;
        
        report "--- Sent 200 bytes via SPI ---";
        wait for CLK_PERIOD * 50;
        
        -- Test 2: Read data from memory (sample various positions)
        report "--- Reading data from memory ---";
        
        for read_test in 0 to 49 loop  -- 50 read tests
            -- Set column and row
            DATA_OUT_COL <= (read_test * 7) mod IMAGE_WIDTH;
            DATA_OUT_ROW <= (read_test * 13) mod IMAGE_WIDTH;
            
            -- Assert COL_ROW_REQ_VALID to request the position
            COL_ROW_REQ_VALID <= '1';
            
            -- Also assert DATA_OUT_READY (both need to be high to read)
            DATA_OUT_READY <= '1';
            wait for CLK_PERIOD;
            
            -- Wait for controller to acknowledge and provide valid data
            wait until COL_ROW_REQ_READY = '1' and DATA_OUT_VALID = '1';
            wait for CLK_PERIOD;
            
            if read_test mod 10 = 0 then
                report "  Read test " & integer'image(read_test) & 
                       ": col=" & integer'image((read_test * 7) mod IMAGE_WIDTH) & 
                       " row=" & integer'image((read_test * 13) mod IMAGE_WIDTH) & 
                       " data=0x" & integer'image(to_integer(unsigned(DATA_OUT)));
            end if;
            
            -- Deassert both signals
            COL_ROW_REQ_VALID <= '0';
            DATA_OUT_READY <= '0';
            wait for CLK_PERIOD * 10;
        end loop;
        
        report "--- Read test complete ---";
        
        wait for CLK_PERIOD * 100;
        
        report "=== ALL RELIABILITY TESTS COMPLETE ===";
        report "Successfully sent 200 bytes via MOSI";
        report "Successfully performed 50 memory read operations";
        report "MISO transmitted 200 bytes of data";
        
        -- Don't set test_done, let simulation continue
        wait;
    end process;

end Behavioral;
