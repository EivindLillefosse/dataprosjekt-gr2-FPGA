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


entity SPI_memory_controller_backup is
    Generic (
        CNN_IMAGE_WIDTH : integer := 28;
        CNN_BUFFER_SIZE : integer := CNN_IMAGE_WIDTH * CNN_IMAGE_WIDTH;  -- 784
        VGA_IMAGE_WIDTH : integer := 200;
        VGA_BUFFER_SIZE : integer := VGA_IMAGE_WIDTH * VGA_IMAGE_WIDTH   -- 40000
    );
    Port ( 
             clk         : in  std_logic;
             rst       : in  std_logic;
             data_in     : in  std_logic_vector(7 downto 0);
             data_in_valid : in  std_logic;
             data_in_ready : out std_logic;
             
             -- CNN interface
             data_out    : out WORD;
             data_out_valid : out std_logic;
             data_out_ready : in  std_logic;
             data_out_col   : in  integer;
             data_out_row   : in  integer;
             col_row_req_ready : out std_logic;
             col_row_req_valid : in  std_logic;
             
             -- VGA port B interface (reads from 200x200 buffer D)
             vga_addr    : in  std_logic_vector(15 downto 0);
             vga_data    : out std_logic_vector(7 downto 0);
             vga_frame_start : in std_logic  -- Pulse at start of each VGA frame
         );
end SPI_memory_controller_backup;


architecture Behavioral of SPI_memory_controller_backup is

    -- Function to calculate address from column and row
    -- Address = row * IMAGE_WIDTH + col
    function calc_address(col : integer; row : integer; image_width : integer) return unsigned is
        variable addr : unsigned(15 downto 0);  -- Extended to 16 bits for 200x200
        variable temp : integer;
    begin
        -- Calculate row * image_width + col manually to avoid resize issues
        temp := (row * image_width) + col;
        
        -- Bounds checking to prevent simulation errors
        if temp < 0 then
            temp := 0;
        elsif temp > 65535 then
            temp := 65535;
        end if;
        
        addr := to_unsigned(temp, 16);
        return addr;
    end function;



COMPONENT BRAM_dual_port
  PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    clkb : IN STD_LOGIC;
    enb : IN STD_LOGIC;
    web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addrb : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
END COMPONENT;

-- Larger BRAM component for 200x200 images (40000 bytes, needs 16-bit addressing)
COMPONENT BRAM_dual_port_large
  PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    clkb : IN STD_LOGIC;
    enb : IN STD_LOGIC;
    web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addrb : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
END COMPONENT;




    -- Write FSM state type - CNN triple buffer + VGA single buffer
    type state_type is (IDLE, 
                        WRITE_A, WRITE_B, WRITE_C,  -- CNN buffers (28x28)
                        WRITE_D,  -- VGA buffer (200x200, single buffer)
                        TRANSITION);
    signal current_state : state_type := IDLE;
    
    -- Read FSM state type
    type read_state_type is (READ_IDLE, WAIT_FOR_DATA, READ_ADDR, WAIT_ADDR_SETTLE, WAIT_BRAM, LOAD_DATA_OUT, MEMORY_UNBUSY);
    signal read_state : read_state_type := READ_IDLE;

    -- bram A signals
    signal bram_A_ena : std_logic := '0';
    signal bram_A_wea : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_A_addra : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_A_dina : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_A_douta : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_A_addr_writea : std_logic_vector(9 downto 0) := (others => '0'); -- Write address
    signal bram_A_addr_reada : std_logic_vector(9 downto 0) := (others => '0');  -- Read address
    signal bram_A_enb : std_logic := '0';
    signal bram_A_web : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_A_addrb : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_A_dinb : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_A_doutb : std_logic_vector(7 downto 0) := (others => '0');

    -- bram B signals
    signal bram_B_ena : std_logic := '0';
    signal bram_B_wea: std_logic_vector(0 downto 0) := (others => '0');
    signal bram_B_addra : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_B_dina : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_B_douta : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_B_addr_writea : std_logic_vector(9 downto 0) := (others => '0'); -- Write address
    signal bram_B_addr_reada : std_logic_vector(9 downto 0) := (others => '0');  -- Read address
    signal bram_B_enb : std_logic := '0';
    signal bram_B_web : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_B_addrb : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_B_dinb : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_B_doutb : std_logic_vector(7 downto 0) := (others => '0');

    -- bram C signals (CNN 28x28)
    signal bram_C_ena : std_logic := '0';
    signal bram_C_wea : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_C_addra : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_C_dina : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_C_douta : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_C_addr_writea : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_C_addr_reada : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_C_enb : std_logic := '0';
    signal bram_C_web : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_C_addrb : std_logic_vector(9 downto 0) := (others => '0');
    signal bram_C_dinb : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_C_doutb : std_logic_vector(7 downto 0) := (others => '0');

    -- VGA bram D signals (200x200, single buffer - continuously overwritten)
    signal bram_D_ena : std_logic := '0';
    signal bram_D_wea : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_D_addra : std_logic_vector(15 downto 0) := (others => '0');
    signal bram_D_dina : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_D_douta : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_D_addr_writea : std_logic_vector(15 downto 0) := (others => '0');
    signal bram_D_enb : std_logic := '0';
    signal bram_D_web : std_logic_vector(0 downto 0) := (others => '0');
    signal bram_D_addrb : std_logic_vector(15 downto 0) := (others => '0');
    signal bram_D_dinb : std_logic_vector(7 downto 0) := (others => '0');
    signal bram_D_doutb : std_logic_vector(7 downto 0) := (others => '0');

    -- Frame type tracking
    signal current_frame_type : std_logic := '0';  -- 0 = CNN (28x28), 1 = VGA (200x200)
    signal next_frame_type : std_logic := '0';     -- Start with CNN frame expected first

    -- Control signals for CNN buffers (28x28)
    signal write_addr_A    : unsigned(9 downto 0) := (others => '0');
    signal write_addr_B    : unsigned(9 downto 0) := (others => '0');
    signal write_addr_C    : unsigned(9 downto 0) := (others => '0');
    signal pixel_count_A   : unsigned(9 downto 0) := (others => '0');
    signal pixel_count_B   : unsigned(9 downto 0) := (others => '0');
    signal pixel_count_C   : unsigned(9 downto 0) := (others => '0');

    -- Control signals for VGA buffer (200x200, single buffer)
    signal write_addr_D    : unsigned(15 downto 0) := (others => '0');
    signal pixel_count_D   : unsigned(15 downto 0) := (others => '0');
    
    -- Status flags for CNN buffers (A,B,C - 28x28)
    signal BRAM_A_busy         : std_logic := '0';
    signal BRAM_B_busy         : std_logic := '0';
    signal BRAM_C_busy         : std_logic := '0';
    signal BRAM_A_last_written : std_logic := '0';
    signal BRAM_B_last_written : std_logic := '0';
    signal BRAM_C_last_written : std_logic := '0';

    -- VGA buffer D is always available for VGA reads (no busy/last_written needed)
    -- It gets continuously overwritten each time a 200x200 frame arrives
    
    -- Read tracking signals (for CNN)
    signal read_count : unsigned(9 downto 0) := (others => '0');
    signal first_read : std_logic := '1';
    signal active_read_buffer : std_logic_vector(1 downto 0) := "00";           -- 00=A, 01=B, 10=C
    
    -- Track which buffer just completed (for transition state)
    signal completed_buffer : std_logic_vector(1 downto 0) := "00";             -- 00=A/D, 01=B/E, 10=C/F
    
    -- VGA interface signals
    -- VGA always reads from buffer D (no multiplexing needed)
    
    -- Dynamic buffer size calculation
    signal MAX_PIXELS_CNN : unsigned(9 downto 0);
    signal MAX_PIXELS_VGA : unsigned(15 downto 0);
    
    -- Memory reset state machine
    type reset_state_type is (RESET_IDLE, RESET_CLEAR_A, RESET_CLEAR_B, RESET_CLEAR_C, RESET_CLEAR_D, RESET_DONE);
    signal reset_state : reset_state_type := RESET_IDLE;
    signal reset_addr : unsigned(9 downto 0) := (others => '0');  -- For CNN buffers A/B/C
    signal reset_addr_vga : unsigned(15 downto 0) := (others => '0');  -- For VGA buffer D
    signal reset_in_progress : std_logic := '0';

  
begin
   
    MAX_PIXELS_CNN <= to_unsigned(CNN_BUFFER_SIZE, 10);  -- 784
    MAX_PIXELS_VGA <= to_unsigned(VGA_BUFFER_SIZE, 16);  -- 40000
    
    -- VGA always reads from buffer D (no address extension needed - already 16-bit)
    
    -- CNN buffers (A, B, C) - always enabled
    bram_A_ena <= '1';
    bram_B_ena <= '1';
    bram_C_ena <= '1';
    bram_A_enb <= '1';
    bram_B_enb <= '1';
    bram_C_enb <= '1';
    bram_A_web <= "0";  
    bram_B_web <= "0";
    bram_C_web <= "0";
    
    -- VGA buffers - only D is used
    bram_D_ena <= '1';
    bram_D_enb <= '1';
    bram_D_web <= "0";  -- Port B is read-only for VGA
    
    -- Connect VGA address directly to buffer D port B (16-bit address)
    bram_D_addrb <= vga_addr;
    bram_D_dinb <= (others => '0');
    
    -- CNN buffers don't need port B for VGA anymore (tied off)
    bram_A_addrb <= (others => '0');
    bram_B_addrb <= (others => '0');
    bram_C_addrb <= (others => '0');
    bram_A_dinb <= (others => '0');
    bram_B_dinb <= (others => '0');
    bram_C_dinb <= (others => '0');
    
    -- col_row_req_ready is high when at least one CNN buffer is complete
    col_row_req_ready <= BRAM_A_last_written or BRAM_B_last_written or BRAM_C_last_written;
    
    -- Address multiplexers for CNN buffers: Select read or write address based on we signal
    -- CNN buffers: Port A can read or write, Port B is for VGA (unused)
    bram_A_addra <= bram_A_addr_writea when bram_A_wea = "1" else bram_A_addr_reada;
    bram_B_addra <= bram_B_addr_writea when bram_B_wea = "1" else bram_B_addr_reada;
    bram_C_addra <= bram_C_addr_writea when bram_C_wea = "1" else bram_C_addr_reada;
    
    -- VGA buffer D: Port A is write-only (SPI), Port B is read-only (VGA)
    bram_D_addra <= bram_D_addr_writea;
    
    -- VGA output - always reads from buffer D (no frame buffering/latching needed)
    vga_data <= bram_D_doutb;
    
    -- Memory reset process: clears all BRAMs when reset is asserted
    memory_reset_process: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                reset_state <= RESET_CLEAR_A;
                reset_addr <= (others => '0');
                reset_addr_vga <= (others => '0');
                reset_in_progress <= '1';
            else
                case reset_state is
                    when RESET_IDLE =>
                        reset_in_progress <= '0';
                        
                    when RESET_CLEAR_A =>
                        -- Clear BRAM A (CNN buffer, 784 bytes)
                        if reset_addr < MAX_PIXELS_CNN then
                            -- Don't assert write enable yet, let main process handle it
                            reset_addr <= reset_addr + 1;
                        else
                            reset_addr <= (others => '0');
                            reset_state <= RESET_CLEAR_B;
                        end if;
                        
                    when RESET_CLEAR_B =>
                        -- Clear BRAM B (CNN buffer, 784 bytes)
                        if reset_addr < MAX_PIXELS_CNN then
                            reset_addr <= reset_addr + 1;
                        else
                            reset_addr <= (others => '0');
                            reset_state <= RESET_CLEAR_C;
                        end if;
                        
                    when RESET_CLEAR_C =>
                        -- Clear BRAM C (CNN buffer, 784 bytes)
                        if reset_addr < MAX_PIXELS_CNN then
                            reset_addr <= reset_addr + 1;
                        else
                            reset_addr <= (others => '0');
                            reset_addr_vga <= (others => '0');
                            reset_state <= RESET_CLEAR_D;
                        end if;
                        
                    when RESET_CLEAR_D =>
                        -- Clear BRAM D (VGA buffer, 40000 bytes)
                        if reset_addr_vga < MAX_PIXELS_VGA then
                            reset_addr_vga <= reset_addr_vga + 1;
                        else
                            reset_addr_vga <= (others => '0');
                            reset_state <= RESET_DONE;
                        end if;
                        
                    when RESET_DONE =>
                        reset_state <= RESET_IDLE;
                        reset_in_progress <= '0';
                        
                    when others =>
                        reset_state <= RESET_IDLE;
                end case;
            end if;
        end if;
    end process;

  BRAM_A_inst : BRAM_dual_port
  PORT MAP (
    clka => clk,
    ena => bram_A_ena,
    wea => bram_A_wea,
    addra => bram_A_addra,
    dina => bram_A_dina,
    douta => bram_A_douta,
    clkb => clk,
    enb => bram_A_enb,
    web => bram_A_web,
    addrb => bram_A_addrb,
    dinb => bram_A_dinb,
    doutb => bram_A_doutb
  );

  BRAM_B_inst : BRAM_dual_port
  PORT MAP (
    clka => clk,
    ena => bram_B_ena,
    wea => bram_B_wea,
    addra => bram_B_addra,
    dina => bram_B_dina,
    douta => bram_B_douta,
    clkb => clk,
    enb => bram_B_enb,
    web => bram_B_web,
    addrb => bram_B_addrb,
    dinb => bram_B_dinb,
    doutb => bram_B_doutb
  );

  BRAM_C_inst : BRAM_dual_port
  PORT MAP (
    clka => clk,
    ena => bram_C_ena,
    wea => bram_C_wea,
    addra => bram_C_addra,
    dina => bram_C_dina,
    douta => bram_C_douta,
    clkb => clk,
    enb => bram_C_enb,
    web => bram_C_web,
    addrb => bram_C_addrb,
    dinb => bram_C_dinb,
    doutb => bram_C_doutb
  );

  -- VGA Buffer D (200x200, single continuously-overwritten buffer)
  BRAM_D_inst : BRAM_dual_port_large
  PORT MAP (
    clka => clk,
    ena => bram_D_ena,
    wea => bram_D_wea,
    addra => bram_D_addra,
    dina => bram_D_dina,
    douta => bram_D_douta,
    clkb => clk,
    enb => bram_D_enb,
    web => bram_D_web,
    addrb => bram_D_addrb,
    dinb => bram_D_dinb,
    doutb => bram_D_doutb
  );

    -- Main control process for CNN triple-buffer + VGA single-buffer management
    control_process_ABC: process(clk, rst)
    begin
        if rst = '1' then
            -- Reset all state and signals
            current_state <= IDLE;
            
            -- Reset CNN buffer counters
            write_addr_A <= (others => '0');
            write_addr_B <= (others => '0');
            write_addr_C <= (others => '0');
            pixel_count_A <= (others => '0');
            pixel_count_B <= (others => '0');
            pixel_count_C <= (others => '0');
            
            -- Reset VGA buffer D counter
            write_addr_D <= (others => '0');
            pixel_count_D <= (others => '0');
            
            -- Reset CNN buffer status flags
            BRAM_A_last_written <= '0';
            BRAM_B_last_written <= '0';
            BRAM_C_last_written <= '0';
            
            completed_buffer <= "00";
            
            -- Reset frame type tracking (start expecting CNN frame)
            current_frame_type <= '0';
            next_frame_type <= '0';
            
            -- Reset CNN write enables
            bram_A_wea <= (others => '0');
            bram_B_wea <= (others => '0');
            bram_C_wea <= (others => '0');
            
            -- Reset VGA write enable
            bram_D_wea <= (others => '0');
            
            -- Reset CNN write addresses
            bram_A_addr_writea <= (others => '0');
            bram_B_addr_writea <= (others => '0');
            bram_C_addr_writea <= (others => '0');
            
            -- Reset VGA write address
            bram_D_addr_writea <= (others => '0');
            
            -- Reset all write data
            bram_A_dina <= (others => '0');
            bram_B_dina <= (others => '0');
            bram_C_dina <= (others => '0');
            bram_D_dina <= (others => '0');
            
            data_in_ready <= '0';
        
        elsif rising_edge(clk) then
            -- Default: no write unless explicitly set
            bram_A_wea <= "0";
            bram_B_wea <= "0";
            bram_C_wea <= "0";
            bram_D_wea <= "0";
            
            -- Handle memory reset: write zeros to all locations
            if reset_in_progress = '1' then
                case reset_state is
                    when RESET_CLEAR_A =>
                        bram_A_wea <= "1";
                        bram_A_dina <= (others => '0');
                        bram_A_addr_writea <= std_logic_vector(reset_addr);
                        
                    when RESET_CLEAR_B =>
                        bram_B_wea <= "1";
                        bram_B_dina <= (others => '0');
                        bram_B_addr_writea <= std_logic_vector(reset_addr);
                        
                    when RESET_CLEAR_C =>
                        bram_C_wea <= "1";
                        bram_C_dina <= (others => '0');
                        bram_C_addr_writea <= std_logic_vector(reset_addr);
                        
                    when RESET_CLEAR_D =>
                        bram_D_wea <= "1";
                        bram_D_dina <= (others => '0');
                        bram_D_addr_writea <= std_logic_vector(reset_addr_vga);
                        
                    when others =>
                        null;
                end case;
            else
                -- Normal operation: handle SPI writes
                -- Ready logic depends on current state and next expected frame type
                if current_state = WRITE_D then
                    data_in_ready <= '1';  -- VGA buffer always ready
                elsif current_state = IDLE and next_frame_type = '1' then
                    data_in_ready <= '1';  -- In IDLE waiting for VGA frame - always ready
                else
                    data_in_ready <= not (BRAM_A_busy and BRAM_B_busy and BRAM_C_busy);  -- CNN needs available buffer
                end if;
        
            -- FSM state switching
            case current_state is
                when IDLE =>
                    -- Determine frame type based on next_frame_type
                    if data_in_valid = '1' and data_in_ready = '1' then
                        -- Debug: Report which path we're taking
                        if next_frame_type = '0' then
                            report "IDLE -> CNN (next_frame_type=0)";
                        else
                            report "IDLE -> VGA (next_frame_type=1)";
                        end if;
                        
                        -- Capture current frame type for this transaction
                        current_frame_type <= next_frame_type;
                        
                        if next_frame_type = '0' then
                            -- CNN frame (28x28) - go to WRITE_A
                            current_state <= WRITE_A;
                            write_addr_A <= (others => '0');
                            pixel_count_A <= (others => '0');
                            bram_A_wea <= "1";
                            bram_A_dina <= data_in;
                            bram_A_addr_writea <= (others => '0');
                            
                            -- Increment for next write
                            write_addr_A <= to_unsigned(1, 10);
                            pixel_count_A <= to_unsigned(1, 10);
                        else
                            -- VGA frame (200x200) - go to WRITE_D
                            current_state <= WRITE_D;
                            write_addr_D <= (others => '0');
                            pixel_count_D <= (others => '0');
                            bram_D_wea <= "1";
                            bram_D_dina <= data_in;
                            bram_D_addr_writea <= (others => '0');
                            
                            -- Increment for next write
                            write_addr_D <= to_unsigned(1, 16);
                            pixel_count_D <= to_unsigned(1, 16);
                        end if;
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
                          
                            bram_A_wea <= "1";
                            bram_A_dina <= data_in;
                            bram_A_addr_writea <= std_logic_vector(write_addr_A);
                            
                            -- Check if THIS write completes the CNN buffer (784 bytes)
                            if write_addr_A = (MAX_PIXELS_CNN - 1) then
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
                           
                            bram_B_wea <= "1";
                            bram_B_dina <= data_in;
                            bram_B_addr_writea <= std_logic_vector(write_addr_B);
                            
                            -- Check if THIS write completes the CNN buffer (784 bytes)
                            if write_addr_B = (MAX_PIXELS_CNN - 1) then
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
        
                            bram_C_wea <= "1";
                            bram_C_dina <= data_in;
                            bram_C_addr_writea <= std_logic_vector(write_addr_C);
                            
                            -- Check if THIS write completes the CNN buffer (784 bytes)
                            if write_addr_C = (MAX_PIXELS_CNN - 1) then
                                current_state <= TRANSITION;
                                completed_buffer <= "10";
                            end if;
                            -- Increment counters AFTER the check
                            write_addr_C <= write_addr_C + 1;
                            pixel_count_C <= pixel_count_C + 1;
                        end if;
                    end if;
                
                when WRITE_D =>
                    -- VGA buffer D - continuously overwrite (no busy check)
                    -- Complete handshake: write when BOTH valid and ready are high
                    if data_in_valid = '1' and data_in_ready = '1' then
                        bram_D_wea <= "1";
                        bram_D_dina <= data_in;
                        bram_D_addr_writea <= std_logic_vector(write_addr_D);
                        
                        -- Check if THIS write completes the VGA buffer (40000 bytes)
                        if write_addr_D = (MAX_PIXELS_VGA - 1) then
                            current_state <= TRANSITION;
                            completed_buffer <= "11";  -- Special marker for VGA complete
                        end if;
                        -- Increment counters AFTER the check
                        write_addr_D <= write_addr_D + 1;
                        pixel_count_D <= pixel_count_D + 1;
                    end if;
                
                when TRANSITION =>
                    -- Wait one cycle for last_written flag update
                    -- Update last_written flags based on completed buffer
                    if completed_buffer = "11" then
                        -- VGA frame completed (buffer D)
                        bram_D_wea <= "0";
                        -- Toggle to expect CNN frame next
                        next_frame_type <= '0';
                        current_state <= IDLE;
                    else
                        -- CNN frame completed (buffer A, B, or C)
                    case completed_buffer is
                        when "00" => -- A completed
                            bram_A_wea <= "0";
                            BRAM_A_last_written <= '1';
                            BRAM_B_last_written <= '0';
                            BRAM_C_last_written <= '0';
                            
                        when "01" => -- B completed
                            bram_B_wea <= "0";
                            BRAM_A_last_written <= '0';
                            BRAM_B_last_written <= '1';
                            BRAM_C_last_written <= '0';
                            
                        when "10" => -- C completed
                            bram_C_wea <= "0";
                            BRAM_A_last_written <= '0';
                            BRAM_B_last_written <= '0';
                            BRAM_C_last_written <= '1';
                            
                    when others =>
                        null;
                    end case;
                    
                    -- Toggle to expect VGA frame next
                    next_frame_type <= '1';
                    
                    -- Return to IDLE to check next_frame_type for proper routing
                    current_state <= IDLE;
                end if;                when others =>
                    current_state <= IDLE;
            end case;
            end if; -- End of reset_in_progress check
        end if;
    end process control_process_ABC;

    read_process: process(clk, rst)
    begin

    if rst = '1' then
        -- Reset read state and signals
        read_state <= READ_IDLE;
        read_count <= (others => '0');
        active_read_buffer <= "00";
        bram_A_addr_reada <= (others => '0');
        bram_B_addr_reada <= (others => '0');
        bram_C_addr_reada <= (others => '0');
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
                -- Detect new read request (requires BOTH data_out_ready AND col_row_req_valid)
                if col_row_req_valid = '1' then
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
                        bram_A_addr_reada <= std_logic_vector(resize(calc_address(data_out_col, data_out_row, CNN_IMAGE_WIDTH), 10));
                    when "01" =>
                        bram_B_addr_reada <= std_logic_vector(resize(calc_address(data_out_col, data_out_row, CNN_IMAGE_WIDTH), 10));
                    when "10" =>
                        bram_C_addr_reada <= std_logic_vector(resize(calc_address(data_out_col, data_out_row, CNN_IMAGE_WIDTH), 10));
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
                if data_out_ready = '1' then
                    read_state <= LOAD_DATA_OUT;
                else
                    read_state <= WAIT_BRAM;
                end if;


            when LOAD_DATA_OUT =>
                -- Load data from the selected buffer
                case active_read_buffer is
                    when "00" =>
                        data_out <= std_logic_vector(resize(unsigned(bram_A_douta), WORD'length));
                    when "01" =>
                        
                        data_out <= std_logic_vector(resize(unsigned(bram_B_douta), WORD'length));
                    when "10" =>
                        
                        data_out <= std_logic_vector(resize(unsigned(bram_C_douta), WORD'length));
                    when others =>
                        null;
                end case;
                
                data_out_valid <= '1';
                if read_count >= MAX_PIXELS_CNN then
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