----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Martin Brekke Nilsen
-- 
-- Create Date: 11/14/2025
-- Design Name: 
-- Module Name: SPI_memory_controller_backup_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: Testbench for dual-frame alternating controller
--              Tests alternating 3x3 CNN frames and 6x6 VGA frames
--              Verifies:
--              - Frame type alternation (CNN -> VGA -> CNN -> VGA)
--              - CNN triple buffer rotation (A->B->C->A)
--              - VGA single buffer continuous overwrite
--              - Proper read routing (CNN from A/B/C, VGA from D)
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
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.ALL;

entity SPI_memory_controller_backup_tb is
end SPI_memory_controller_backup_tb;

architecture Behavioral of SPI_memory_controller_backup_tb is
    -- Test image sizes
    constant CNN_IMAGE_WIDTH : integer := 3;
    constant VGA_IMAGE_WIDTH : integer := 6;
    constant CNN_PIXELS : integer := CNN_IMAGE_WIDTH * CNN_IMAGE_WIDTH;  -- 9
    constant VGA_PIXELS : integer := VGA_IMAGE_WIDTH * VGA_IMAGE_WIDTH;  -- 36
    
    -- Test configuration: send multiple alternating frames
    constant NUM_CNN_FRAMES : integer := 5;  -- Test CNN triple buffer rotation
    constant NUM_VGA_FRAMES : integer := 5;  -- Test VGA overwrite
    constant TOTAL_FRAMES : integer := NUM_CNN_FRAMES + NUM_VGA_FRAMES;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- DUT signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal data_in : std_logic_vector(7 downto 0) := (others => '0');
    signal data_in_valid : std_logic := '0';
    signal data_in_ready : std_logic;
    
    -- CNN interface
    signal data_out : WORD;
    signal data_out_valid : std_logic := '0';
    signal data_out_ready : std_logic := '0';
    signal data_out_col : integer := 0;
    signal data_out_row : integer := 0;
    signal col_row_req_ready : std_logic;
    signal col_row_req_valid : std_logic := '0';
    
    -- VGA interface
    signal vga_addr : std_logic_vector(15 downto 0) := (others => '0');
    signal vga_data : std_logic_vector(7 downto 0);
    signal vga_frame_start : std_logic := '0';
    
    -- Test control signals
    signal test_done : boolean := false;
    signal pixels_sent : integer := 0;
    signal frames_completed : integer := 0;
    signal current_frame_is_cnn : boolean := true;  -- Start with CNN frame
    
    -- Component declaration
    component SPI_memory_controller_backup is
        generic (
            CNN_IMAGE_WIDTH : integer := 3;
            CNN_BUFFER_SIZE : integer := 9;
            VGA_IMAGE_WIDTH : integer := 6;
            VGA_BUFFER_SIZE : integer := 36
        );
        port (
            clk : in std_logic;
            rst : in std_logic;
            data_in : in std_logic_vector(7 downto 0);
            data_in_valid : in std_logic;
            data_in_ready : out std_logic;
            data_out : out WORD;
            data_out_valid : out std_logic;
            data_out_ready : in std_logic;
            data_out_col : in integer;
            data_out_row : in integer;
            col_row_req_ready : out std_logic;
            col_row_req_valid : in std_logic;
            vga_addr : in std_logic_vector(15 downto 0);
            vga_data : out std_logic_vector(7 downto 0);
            vga_frame_start : in std_logic
        );
    end component;

begin
    -- Instantiate the DUT
    DUT: SPI_memory_controller_backup
        generic map (
            CNN_IMAGE_WIDTH => CNN_IMAGE_WIDTH,
            CNN_BUFFER_SIZE => CNN_PIXELS,
            VGA_IMAGE_WIDTH => VGA_IMAGE_WIDTH,
            VGA_BUFFER_SIZE => VGA_PIXELS
        )
        port map (
            clk => clk,
            rst => rst,
            data_in => data_in,
            data_in_valid => data_in_valid,
            data_in_ready => data_in_ready,
            data_out => data_out,
            data_out_valid => data_out_valid,
            data_out_ready => data_out_ready,
            data_out_col => data_out_col,
            data_out_row => data_out_row,
            col_row_req_ready => col_row_req_ready,
            col_row_req_valid => col_row_req_valid,
            vga_addr => vga_addr,
            vga_data => vga_data,
            vga_frame_start => vga_frame_start
        );
    
    -- Clock generation
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
    
    -- Input data provider - alternates between CNN and VGA frames
    input_provider: process
        variable pixel_value : integer := 0;
        variable pixel_in_current_frame : integer := 0;
        variable current_frame_size : integer := CNN_PIXELS;
        variable cnn_frame_count : integer := 0;
        variable vga_frame_count : integer := 0;
    begin
        -- Wait for reset to deassert
        wait until rst = '0';
        wait until rising_edge(clk);
        
        report "========================================";
        report "Starting Dual-Frame SPI Controller Test";
        report "CNN frame size: " & integer'image(CNN_PIXELS) & " pixels (3x3)";
        report "VGA frame size: " & integer'image(VGA_PIXELS) & " pixels (6x6)";
        report "Total frames to send: " & integer'image(TOTAL_FRAMES);
        report "========================================";
        report "";
        
        -- Enable valid signal (keep high for fast testing)
        data_in_valid <= '1';
        
        -- Send alternating CNN and VGA frames
        while frames_completed < TOTAL_FRAMES loop
            -- Determine current frame type and size
            if current_frame_is_cnn then
                current_frame_size := CNN_PIXELS;
            else
                current_frame_size := VGA_PIXELS;
            end if;
            
            -- Send one complete frame
            pixel_in_current_frame := 0;
            
            if current_frame_is_cnn then
                report "";
                report "=== Starting CNN Frame #" & integer'image(cnn_frame_count) & 
                       " (Overall frame #" & integer'image(frames_completed) & ") ===";
            else
                report "";
                report "=== Starting VGA Frame #" & integer'image(vga_frame_count) & 
                       " (Overall frame #" & integer'image(frames_completed) & ") ===";
            end if;
            
            while pixel_in_current_frame < current_frame_size loop
                -- Calculate pixel value: frame_type (100=CNN, 200=VGA) + pixel position
                if current_frame_is_cnn then
                    pixel_value := 100 + pixel_in_current_frame;  -- CNN: 100-108
                else
                    pixel_value := 200 + pixel_in_current_frame;  -- VGA: 200-235
                end if;
                
                data_in <= std_logic_vector(to_unsigned(pixel_value mod 256, 8));
                
                -- Wait for handshake
                wait until rising_edge(clk);
                if data_in_valid = '1' and data_in_ready = '1' then
                    if pixel_in_current_frame mod 9 = 0 then
                        report "  Pixel " & integer'image(pixel_in_current_frame) & 
                               ": value=" & integer'image(pixel_value);
                    end if;
                    
                    pixel_in_current_frame := pixel_in_current_frame + 1;
                    pixels_sent <= pixels_sent + 1;
                end if;
            end loop;
            
            -- Frame complete
            if current_frame_is_cnn then
                report "=== CNN Frame #" & integer'image(cnn_frame_count) & " COMPLETE ===";
                cnn_frame_count := cnn_frame_count + 1;
                current_frame_is_cnn <= false;  -- Next frame is VGA
            else
                report "=== VGA Frame #" & integer'image(vga_frame_count) & " COMPLETE ===";
                vga_frame_count := vga_frame_count + 1;
                current_frame_is_cnn <= true;   -- Next frame is CNN
            end if;
            
            frames_completed <= frames_completed + 1;
            
            -- Small gap between frames
            wait for CLK_PERIOD * 5;
        end loop;
        
        data_in_valid <= '0';
        
        report "";
        report "========================================";
        report "All frames sent successfully";
        report "CNN frames: " & integer'image(cnn_frame_count);
        report "VGA frames: " & integer'image(vga_frame_count);
        report "Total pixels: " & integer'image(pixels_sent);
        report "========================================";
        
        wait;
    end process;
    
    -- CNN read test - read from completed CNN buffers
    cnn_read_test: process
        variable col, row : integer;
        variable read_count : integer := 0;
    begin
        wait until rst = '0';
        col_row_req_valid <= '0';
        data_out_ready <= '0';
        
        -- Wait for first CNN frame to complete
        wait until frames_completed >= 1;
        wait until col_row_req_ready = '1';
        wait for CLK_PERIOD * 10;
        
        report "";
        report "=== Starting CNN Read Test ===";
        report "";
        
        -- Perform some read transactions from CNN buffers
        for read_idx in 0 to 8 loop
            col := read_idx mod CNN_IMAGE_WIDTH;
            row := read_idx / CNN_IMAGE_WIDTH;
            
            -- Clean state
            col_row_req_valid <= '0';
            data_out_ready <= '0';
            wait for CLK_PERIOD * 2;
            
            -- Assert col/row request
            data_out_col <= col;
            data_out_row <= row;
            col_row_req_valid <= '1';
            wait for CLK_PERIOD * 4;
            
            -- Trigger data load
            data_out_ready <= '1';
            
            -- Wait for valid data
            wait until data_out_valid = '1' for CLK_PERIOD * 10;
            if data_out_valid = '1' then
                report "  CNN Read [" & integer'image(row) & "," & integer'image(col) & 
                       "]: data=0x" & integer'image(to_integer(unsigned(data_out)));
                read_count := read_count + 1;
            else
                report "  ERROR: Timeout on CNN read!";
            end if;
            
            -- Deassert
            col_row_req_valid <= '0';
            data_out_ready <= '0';
            wait for CLK_PERIOD * 5;
        end loop;
        
        report "";
        report "=== CNN Read Test Complete (" & integer'image(read_count) & " reads) ===";
        report "";
        
        wait;
    end process;
    
    -- VGA read test - continuously read from VGA buffer D
    vga_read_test: process
        variable vga_addr_int : integer := 0;
    begin
        wait until rst = '0';
        
        -- Wait for first VGA frame to complete
        wait until frames_completed >= 2;
        wait for CLK_PERIOD * 20;
        
        report "";
        report "=== Starting VGA Read Test ===";
        report "";
        
        -- Read several VGA addresses
        for read_idx in 0 to 9 loop
            vga_addr_int := read_idx;
            vga_addr <= std_logic_vector(to_unsigned(vga_addr_int, 16));
            
            wait for CLK_PERIOD * 2;
            
            report "  VGA Read [addr=" & integer'image(vga_addr_int) & 
                   "]: data=0x" & integer'image(to_integer(unsigned(vga_data)));
        end loop;
        
        report "";
        report "=== VGA Read Test Complete ===";
        report "";
        
        wait;
    end process;
    
    -- Monitor frame alternation and buffer state
    frame_monitor: process(clk)
        variable last_frames_completed : integer := -1;
    begin
        if rising_edge(clk) and rst = '0' then
            if frames_completed /= last_frames_completed then
                last_frames_completed := frames_completed;
                
                if frames_completed > 0 then
                    report "";
                    report ">>> Frame Completed: Total=" & integer'image(frames_completed) & 
                           " of " & integer'image(TOTAL_FRAMES);
                    report "";
                end if;
            end if;
        end if;
    end process;
    
    -- Test control
    test_control: process
    begin
        rst <= '1';
        report "";
        report "============================================================";
        report "   DUAL-FRAME ALTERNATING CONTROLLER TESTBENCH             ";
        report "   CNN: 3x3 (9 pixels) - Triple buffer A/B/C               ";
        report "   VGA: 6x6 (36 pixels) - Single buffer D                  ";
        report "   Pattern: CNN -> VGA -> CNN -> VGA -> ...                ";
        report "============================================================";
        report "";
        wait for CLK_PERIOD * 5;
        rst <= '0';
        report ">> Test starting...";
        report "";
        
        -- Wait for all frames to complete (with timeout)
        wait until frames_completed >= TOTAL_FRAMES for CLK_PERIOD * 50000;
        
        if frames_completed < TOTAL_FRAMES then
            report "WARNING: Test timeout! Only " & integer'image(frames_completed) & 
                   " of " & integer'image(TOTAL_FRAMES) & " frames completed" severity warning;
        else
            wait for CLK_PERIOD * 500;
        end if;
        
        report "";
        report "============================================================";
        report "   TEST COMPLETE                                            ";
        report "   Total frames: " & integer'image(frames_completed);
        report "   Total pixels: " & integer'image(pixels_sent);
        report "   Expected: CNN/VGA alternation with proper buffer routing";
        report "============================================================";
        report "";
        
        test_done <= true;
        wait;
    end process;

end Behavioral;
