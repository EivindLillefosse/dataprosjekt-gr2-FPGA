----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Martin Brekke Nilsen
-- 
-- Create Date: 09.10.2025 12:15:37
-- Design Name: 
-- Module Name: SPI_memory_controller - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.types_pkg.ALL;


use IEEE.NUMERIC_STD.ALL;


entity SPI_memory_controller is
    Generic (
        
        IMAGE_WIDTH : integer := 28;
        BUFFER_SIZE : integer := IMAGE_WIDTH*IMAGE_WIDTH
    );
    Port ( 
             clk         : in  std_logic;
             rst       : in  std_logic;
             data_in     : in  std_logic_vector(7 downto 0);
             data_in_valid : in  std_logic;
             data_in_ready : out std_logic;
             
             data_out    : out WORD;
             data_out_valid : out std_logic;
             data_out_ready : in  std_logic;
             data_out_col   : in  integer;
             data_out_row   : in  integer
         );
end SPI_memory_controller;


architecture Behavioral of SPI_memory_controller is

    -- Function to calculate address from column and row
    -- Address = row * IMAGE_WIDTH + col
    function calc_address(col : integer; row : integer; image_width : integer) return unsigned is
        variable addr : unsigned(9 downto 0);
        variable temp : integer;
    begin
        -- Calculate row * image_width + col manually to avoid resize issues
        temp := (row * image_width) + col;
        addr := to_unsigned(temp, 10);
        return addr;
    end function;


COMPONENT SPI_bram_A
     PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) 
  );
END COMPONENT;






    -- Write FSM state type
    type state_type is (IDLE, WRITE_A, WRITE_B, WRITE_C, TRANSITION);
    signal current_state : state_type := IDLE;
    
    -- Read FSM state type
    type read_state_type is (READ_IDLE, WAIT_FOR_DATA, READ_ADDR, WAIT_ADDR_SETTLE, WAIT_BRAM, LOAD_DATA_OUT, MEMORY_UNBUSY);
    signal read_state : read_state_type := READ_IDLE;

    -- bram A signals
    signal bram_A_en : std_logic := '0';
    signal bram_A_we : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_A_addr : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_A_din : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_A_dout : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_A_addr_write : std_logic_vector(9 downto 0) := (others => '0'); -- Write address
    signal bram_A_addr_read : std_logic_vector(9 downto 0) := (others => '0');  -- Read address

    -- bram B signals
    signal bram_B_en : std_logic := '0';
    signal bram_B_we : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_B_addr : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_B_din : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_B_dout : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_B_addr_write : std_logic_vector(9 downto 0) := (others => '0'); -- Write address
    signal bram_B_addr_read : std_logic_vector(9 downto 0) := (others => '0');  -- Read address

    -- bram C signals
    signal bram_C_en : std_logic := '0';
    signal bram_C_we : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_C_addr : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_C_din : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_C_dout : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_C_addr_write : std_logic_vector(9 downto 0) := (others => '0'); -- Write address
    signal bram_C_addr_read : std_logic_vector(9 downto 0) := (others => '0');  -- Read address

    -- Control signals
    signal write_addr_A    : unsigned(9 downto 0) := (others => '0'); -- Address counter for BRAM A (0 to 783)
    signal write_addr_B    : unsigned(9 downto 0) := (others => '0'); -- Address counter for BRAM B (0 to 783)
    signal write_addr_C    : unsigned(9 downto 0) := (others => '0'); -- Address counter for BRAM C (0 to 783)
    signal pixel_count_A   : unsigned(9 downto 0) := (others => '0'); -- Count pixels written to A (0 to 784)
    signal pixel_count_B   : unsigned(9 downto 0) := (others => '0'); -- Count pixels written to B (0 to 784)
    signal pixel_count_C   : unsigned(9 downto 0) := (others => '0'); -- Count pixels written to C (0 to 784)
    
    -- Status flags for each buffer
    signal BRAM_A_busy         : std_logic := '0';
    signal BRAM_B_busy         : std_logic := '0';
    signal BRAM_C_busy         : std_logic := '0';
    signal BRAM_A_last_written : std_logic := '0';
    signal BRAM_B_last_written : std_logic := '0';
    signal BRAM_C_last_written : std_logic := '0';
    
    -- Read tracking signals
    signal read_count : unsigned(9 downto 0) := (others => '0');                -- Count how many addresses have been read
    signal first_read : std_logic := '1';                                       -- Track if this is the first read
    signal active_read_buffer : std_logic_vector(1 downto 0) := "00";           -- 00=A, 01=B, 10=C
    
    -- Track which buffer just completed (for transition state)
    signal completed_buffer : std_logic_vector(1 downto 0) := "00";             -- 00=A, 01=B, 10=C
    
    -- Dynamic buffer size calculation
    signal MAX_PIXELS    : unsigned(9 downto 0);

  
begin
   
    MAX_PIXELS <= to_unsigned(BUFFER_SIZE, 10);
    
    bram_A_en <= '1';
    bram_B_en <= '1';
    bram_C_en <= '1';
    
    -- Address multiplexers: Select read or write address based on we signal
    -- When writing (we='1'), use write address; when reading (we='0'), use read address
    bram_A_addr <= bram_A_addr_write when bram_A_we = "1" else bram_A_addr_read;
    bram_B_addr <= bram_B_addr_write when bram_B_we = "1" else bram_B_addr_read;
    bram_C_addr <= bram_C_addr_write when bram_C_we = "1" else bram_C_addr_read;

  BRAM_A_inst : SPI_bram_A
  PORT MAP (
    clka => clk,
    ena => bram_A_en,
    wea => bram_A_we,
    addra => bram_A_addr,
    dina => bram_A_din,
    douta => bram_A_dout
  );

  BRAM_B_inst : SPI_bram_A
  PORT MAP (
    clka => clk,
    ena => bram_B_en,
    wea => bram_B_we,
    addra => bram_B_addr,
    dina => bram_B_din,
    douta => bram_B_dout
  );

  BRAM_C_inst : SPI_bram_A
  PORT MAP (
    clka => clk,
    ena => bram_C_en,
    wea => bram_C_we,
    addra => bram_C_addr,
    dina => bram_C_din,
    douta => bram_C_dout
  );

    -- Main control process for three-buffer write management with flexible transitions
    control_process_ABC: process(clk, rst)
    begin
        if rst = '1' then
            -- Reset all state and signals
            current_state <= IDLE;
            write_addr_A <= (others => '0');
            write_addr_B <= (others => '0');
            write_addr_C <= (others => '0');
            pixel_count_A <= (others => '0');
            pixel_count_B <= (others => '0');
            pixel_count_C <= (others => '0');
            
            -- Reset status flags
            
            BRAM_A_last_written <= '0';
            BRAM_B_last_written <= '0';
            BRAM_C_last_written <= '0';
            completed_buffer <= "00";
            
            
            bram_A_we <= (others => '0');
            bram_B_we <= (others => '0');
            bram_C_we <= (others => '0');
            bram_A_addr_write <= (others => '0');
            bram_B_addr_write <= (others => '0');
            bram_C_addr_write <= (others => '0');
            bram_A_din <= (others => '0');
            bram_B_din <= (others => '0');
            bram_C_din <= (others => '0');
            data_in_ready <= '0';
        
        elsif rising_edge(clk) then
            -- Default: no write unless explicitly set
            bram_A_we <= "0";
            bram_B_we <= "0";
            bram_C_we <= "0";
            
            data_in_ready <= not (BRAM_A_busy and BRAM_B_busy and BRAM_C_busy);
        
            -- FSM state switching
            case current_state is
                when IDLE =>
                    -- On first data_in_valid, transition to WRITE_A and perform first write
                    if data_in_valid = '1' and data_in_ready = '1' then
                        current_state <= WRITE_A;

                        -- Initialize BRAM A for writing
                        write_addr_A <= (others => '0');
                        pixel_count_A <= (others => '0');
                        bram_A_we <= "1";
                        bram_A_din <= data_in;
                        bram_A_addr_write <= (others => '0');
                        
                        -- Increment for next write
                        write_addr_A <= to_unsigned(1, 10);
                        pixel_count_A <= to_unsigned(1, 10);
                    end if;
                
                when WRITE_A =>
                    -- Check if A became busy, if so switch to another buffer
                    if BRAM_A_busy = '1' then
                        if BRAM_B_busy = '0' then
                            current_state <= WRITE_B;
                            write_addr_B <= (others => '0');
                            pixel_count_B <= (others => '0');
                        elsif BRAM_C_busy = '0' then
                            current_state <= WRITE_C;
                            write_addr_C <= (others => '0');
                            pixel_count_C <= (others => '0');
                        end if;
                    else
                        -- Complete handshake: write when BOTH valid and ready are high
                        if data_in_valid = '1' and data_in_ready = '1' then
                          
                            bram_A_we <= "1";
                            bram_A_din <= data_in;
                            bram_A_addr_write <= std_logic_vector(write_addr_A);
                            
                            -- Check if THIS write completes the buffer
                            if write_addr_A = (MAX_PIXELS - 1) then
                                current_state <= TRANSITION;
                                completed_buffer <= "00"; 
                            end if;
                            -- Increment counters AFTER the check
                            write_addr_A <= write_addr_A + 1;
                            pixel_count_A <= pixel_count_A + 1;
                        end if;
                    end if;
                
                when WRITE_B =>
                    -- Check if B became busy, if so switch to another buffer
                    if BRAM_B_busy = '1' then
                        if BRAM_A_busy = '0' then
                            current_state <= WRITE_A;
                            write_addr_A <= (others => '0');
                            pixel_count_A <= (others => '0');
                        elsif BRAM_C_busy = '0' then
                            current_state <= WRITE_C;
                            write_addr_C <= (others => '0');
                            pixel_count_C <= (others => '0');
                        end if;
                    else
                        -- Complete handshake: write when BOTH valid and ready are high
                        if data_in_valid = '1' and data_in_ready = '1' then
                           
                            bram_B_we <= "1";
                            bram_B_din <= data_in;
                            bram_B_addr_write <= std_logic_vector(write_addr_B);
                            
                            -- Check if THIS write completes the buffer
                            if write_addr_B = (MAX_PIXELS - 1) then
                                current_state <= TRANSITION;
                                completed_buffer <= "01"; 
                            end if;
                            -- Increment counters AFTER the check
                            write_addr_B <= write_addr_B + 1;
                            pixel_count_B <= pixel_count_B + 1;
                        end if;
                    end if;
                
                when WRITE_C =>
                    -- Check if C became busy, if so switch to another buffer
                    if BRAM_C_busy = '1' then
                        if BRAM_A_busy = '0' then
                            current_state <= WRITE_A;
                            write_addr_A <= (others => '0');
                            pixel_count_A <= (others => '0');
                        elsif BRAM_B_busy = '0' then
                            current_state <= WRITE_B;
                            write_addr_B <= (others => '0');
                            pixel_count_B <= (others => '0');
                        end if;
                    else
                        -- Complete handshake: write when BOTH valid and ready are high
                        if data_in_valid = '1' and data_in_ready = '1' then
        
                            bram_C_we <= "1";
                            bram_C_din <= data_in;
                            bram_C_addr_write <= std_logic_vector(write_addr_C);
                            
                            -- Check if THIS write completes the buffer
                            if write_addr_C = (MAX_PIXELS - 1) then
                                current_state <= TRANSITION;
                                completed_buffer <= "10";
                            end if;
                            -- Increment counters AFTER the check
                            write_addr_C <= write_addr_C + 1;
                            pixel_count_C <= pixel_count_C + 1;
                        end if;
                    end if;
                
                when TRANSITION =>
                    -- Wait one cycle for last_written flag update
                    -- Update last_written flags based on completed buffer
                    case completed_buffer is
                        when "00" => -- A completed
                            bram_A_we <= "0";
                            BRAM_A_last_written <= '1';
                            BRAM_B_last_written <= '0';
                            BRAM_C_last_written <= '0';
                            
                        when "01" => -- B completed
                            bram_B_we <= "0";
                            BRAM_A_last_written <= '0';
                            BRAM_B_last_written <= '1';
                            BRAM_C_last_written <= '0';
                            
                        when "10" => -- C completed
                            bram_C_we <= "0";
                            BRAM_A_last_written <= '0';
                            BRAM_B_last_written <= '0';
                            BRAM_C_last_written <= '1';
                            
                        when others =>
                            null;
                    end case;
                    
                    -- Select next buffer to write (any non-busy buffer)
                    -- Priority: A > B > C (but skip busy buffers)
                    if BRAM_A_busy = '0' and completed_buffer /= "00" then
                        current_state <= WRITE_A;
                        write_addr_A <= (others => '0');
                        pixel_count_A <= (others => '0');
                    elsif BRAM_B_busy = '0' and completed_buffer /= "01" then
                        current_state <= WRITE_B;
                        write_addr_B <= (others => '0');
                        pixel_count_B <= (others => '0');
                    elsif BRAM_C_busy = '0' and completed_buffer /= "10" then
                        current_state <= WRITE_C;
                        write_addr_C <= (others => '0');
                        pixel_count_C <= (others => '0');
                    else
                        -- All other buffers are busy, stay in TRANSITION and wait (shouldnt happen)
                        current_state <= TRANSITION;
                    end if;
                
                when others =>
                    current_state <= IDLE;
            end case;
        end if;
    end process control_process_ABC;

    read_process: process(clk, rst)
    begin

    if rst = '1' then
        -- Reset read state and signals
        read_state <= READ_IDLE;
        read_count <= (others => '0');
        active_read_buffer <= "00";
        bram_A_addr_read <= (others => '0');
        bram_B_addr_read <= (others => '0');
        bram_C_addr_read <= (others => '0');
        data_out_valid <= '0';
        data_out <= (others => '0');
        BRAM_A_busy <= '0';
        BRAM_B_busy <= '0';
        BRAM_C_busy <= '0';
        first_read <= '1';
       

    elsif rising_edge(clk) then
        
        -- Maintain busy flags throughout the read session (except when explicitly clearing)
        -- This ensures busy stays high for all 784 reads, not just when first set
        if read_state /= MEMORY_UNBUSY and read_state /= READ_IDLE and first_read = '0' then
            case active_read_buffer is
                when "00" =>
                    BRAM_A_busy <= '1';
                when "01" =>
                    BRAM_B_busy <= '1';
                when "10" =>
                    BRAM_C_busy <= '1';
                when others =>
                    null;
            end case;
        end if;

        -- FSM Read switching

        case read_state is
            when READ_IDLE =>
                data_out_valid <= '0';
                -- Detect new read request
                if data_out_ready = '1' then
                    if first_read = '1' then
                        -- First read: check if any buffer is complete
                        if BRAM_A_last_written = '1' or BRAM_B_last_written = '1' or BRAM_C_last_written = '1' then
                            
                            if BRAM_A_last_written = '1' then
                                active_read_buffer <= "00"; -- Read from A
                                BRAM_A_busy <= '1';
                            elsif BRAM_B_last_written = '1' then
                                active_read_buffer <= "01"; -- Read from B
                                BRAM_B_busy <= '1';
                            elsif BRAM_C_last_written = '1' then
                                active_read_buffer <= "10"; -- Read from C
                                BRAM_C_busy <= '1';
                            end if;

                            first_read <= '0';
                            -- Move directly to READ_ADDR
                            read_state <= READ_ADDR;
                        else
                            -- No buffer complete yet, wait for data
                            read_state <= WAIT_FOR_DATA;
                        end if;
                    else
                        -- Not first read, buffer already selected
                        read_state <= READ_ADDR;
                    end if;
                else
                    read_state <= READ_IDLE;
                end if;
            
            when WAIT_FOR_DATA =>

                -- Wait until at least one buffer has been fully written
                data_out_valid <= '0';
                if BRAM_A_last_written = '1' or BRAM_B_last_written = '1' or BRAM_C_last_written = '1' then
                    -- A buffer is now complete, select it
                    if BRAM_A_last_written = '1' then
                        active_read_buffer <= "00"; -- Read from A
                        BRAM_A_busy <= '1';
                    elsif BRAM_B_last_written = '1' then
                        active_read_buffer <= "01"; -- Read from B
                        BRAM_B_busy <= '1';
                    elsif BRAM_C_last_written = '1' then
                        active_read_buffer <= "10"; -- Read from C
                        BRAM_C_busy <= '1';
                    end if;
                    first_read <= '0';

                    -- Now proceed to read
                    read_state <= READ_ADDR;
                else
                    -- Still waiting, stay in this state
                    read_state <= WAIT_FOR_DATA;
                end if;
        
            when READ_ADDR =>
                -- Calculate address from col/row and set for the active buffer
                -- Address will be registered at END of this cycle
                case active_read_buffer is
                    when "00" =>
                        bram_A_addr_read <= std_logic_vector(calc_address(data_out_col, data_out_row, IMAGE_WIDTH));
                    when "01" =>
                        bram_B_addr_read <= std_logic_vector(calc_address(data_out_col, data_out_row, IMAGE_WIDTH));
                    when "10" =>
                        bram_C_addr_read <= std_logic_vector(calc_address(data_out_col, data_out_row, IMAGE_WIDTH));
                    when others =>
                        null;
                end case;
                read_count <= read_count + 1;
                -- Move to WAIT_ADDR_SETTLE to let address propagate to BRAM (takes a cycle)
                read_state <= WAIT_ADDR_SETTLE;
                
            when WAIT_ADDR_SETTLE =>
                -- Wait one cycle for bram_X_addr_read to be updated
                -- BRAM now sees the new address and starts fetching
                read_state <= WAIT_BRAM;
            
            when WAIT_BRAM =>
                -- Wait one cycle for BRAM to fetch data
                -- Address was set two cycles ago, data will be ready next cycle
                read_state <= LOAD_DATA_OUT;                
            
            when LOAD_DATA_OUT =>
                -- Load data from the selected buffer
                case active_read_buffer is
                    when "00" =>
                        data_out <= std_logic_vector(resize(unsigned(bram_A_dout), WORD'length));
                    when "01" =>
                        
                        data_out <= std_logic_vector(resize(unsigned(bram_B_dout), WORD'length));
                    when "10" =>
                        
                        data_out <= std_logic_vector(resize(unsigned(bram_C_dout), WORD'length));
                    when others =>
                        null;
                end case;
                
                data_out_valid <= '1';
                if read_count >= MAX_PIXELS then
                    read_state <= MEMORY_UNBUSY;
                else
                    read_state <= READ_IDLE;
                end if;
                
                -- Check for handshake completion
                
                -- enters unbusy after the entire memory is read.
                when MEMORY_UNBUSY =>
                    -- Clear busy flag for the active buffer
                    BRAM_A_busy <= '0';
                    BRAM_B_busy <= '0';
                    BRAM_C_busy <= '0';
                    read_count <= (others => '0');
                    
                    read_state <= READ_IDLE;
                    first_read <= '1';
                    data_out_valid <= '0';
                when others =>
                        null;
                end case;

    end if;
end process read_process;

end Behavioral;
