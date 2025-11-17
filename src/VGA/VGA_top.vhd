----------------------------------------------------------------------------------
-- Company: Digilent
-- Engineer: Arthur Brown
-- 
--
-- Create Date:    13:01:51 02/15/2013 
-- Project Name:   pmodvga
-- Target Devices: arty
-- Tool versions:  2016.4
-- Additional Comments: 
--
-- Copyright Digilent 2017
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;  -- For to_unsigned function
use work.types_pkg.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity vga_top is
    Generic (
        IMAGE_WIDTH  : natural := 28;
        IMAGE_HEIGHT : natural := 28
    );
    Port ( CLK_I : in  STD_LOGIC;  -- 100 MHz system clock
           RST : in STD_LOGIC;      -- Reset
           
           -- VGA outputs
           VGA_HS_O : out  STD_LOGIC;
           VGA_VS_O : out  STD_LOGIC;
           VGA_R : out  STD_LOGIC_VECTOR (3 downto 0);
           VGA_B : out  STD_LOGIC_VECTOR (3 downto 0);
           VGA_G : out  STD_LOGIC_VECTOR (3 downto 0);
           
           -- Interface to SPI Memory Controller (port B - reads from busy buffer)
           spi_vga_addr : out STD_LOGIC_VECTOR (9 downto 0);  -- Address to SPI controller
           spi_vga_data : in  STD_LOGIC_VECTOR (7 downto 0);  -- Data from SPI controller
           vga_frame_start : out STD_LOGIC;  -- Pulse at start of each frame

           output_guess : in WORD  -- CNN output guess to display
    );
end vga_top;

architecture Behavioral of vga_top is

component clk_wiz_0
port
 (
    clk_in1  : in  std_logic;           -- 100 MHz system clock
    reset    : in  std_logic;           -- Active high reset
    clk_out1 : out std_logic;           -- 25 MHz VGA pixel clock
    locked   : out std_logic            -- Clock stable indicator (optional
 );
end component;


--***640x480@60Hz***--  Requires 25 MHz clock
-- For synthesis with real VGA, use 640x480:
constant FRAME_WIDTH : natural := 640;
constant FRAME_HEIGHT : natural := 480;
constant H_FP : natural := 16; --H front porch width (pixels)
constant H_PW : natural := 96; --H sync pulse width (pixels)
constant H_MAX : natural := 800; --H total period (pixels)
constant V_FP : natural := 10; --V front porch width (lines)
constant V_PW : natural := 2; --V sync pulse width (lines)
constant V_MAX : natural := 525; --V total period (lines)

-- For simulation testing with small images, use reduced frame size:
-- constant FRAME_WIDTH : natural := 16;
-- constant FRAME_HEIGHT : natural := 12;
-- constant H_FP : natural := 2;  -- Reduced for simulation
-- constant H_PW : natural := 2;  -- Reduced for simulation
-- constant H_MAX : natural := FRAME_WIDTH + H_FP + H_PW + 2; -- Total period
-- constant V_FP : natural := 1;  -- Reduced for simulation
-- constant V_PW : natural := 1;  -- Reduced for simulation
-- constant V_MAX : natural := FRAME_HEIGHT + V_FP + V_PW + 2; -- Total period

constant H_POL : std_logic := '0';
constant V_POL : std_logic := '0';

-- Image Display Constants (from generics)
-- SCALE_X/Y calculated to fit image to screen
constant SCALE_X : natural := FRAME_WIDTH / IMAGE_WIDTH;   -- Pixels per image pixel horizontally
constant SCALE_Y : natural := FRAME_HEIGHT / IMAGE_HEIGHT; -- Pixels per image pixel vertically
constant OFFSET_X : natural := (FRAME_WIDTH - IMAGE_WIDTH * SCALE_X) / 2;   -- Center horizontally
constant OFFSET_Y : natural := (FRAME_HEIGHT - IMAGE_HEIGHT * SCALE_Y) / 2; -- Center vertically

signal pxl_clk : std_logic;
signal clk_locked : std_logic;
signal pxl_clk_rst : std_logic;  -- Gated reset for pixel clock domain
signal active : std_logic;

signal h_cntr_reg : std_logic_vector(11 downto 0) := (others =>'0');
signal v_cntr_reg : std_logic_vector(11 downto 0) := (others =>'0');

signal h_sync_reg : std_logic := not(H_POL);
signal v_sync_reg : std_logic := not(V_POL);

signal h_sync_dly_reg : std_logic := not(H_POL);
signal v_sync_dly_reg : std_logic :=  not(V_POL);

signal vga_red_reg : std_logic_vector(3 downto 0) := (others =>'0');
signal vga_green_reg : std_logic_vector(3 downto 0) := (others =>'0');
signal vga_blue_reg : std_logic_vector(3 downto 0) := (others =>'0');

signal vga_red : std_logic_vector(3 downto 0);
signal vga_green : std_logic_vector(3 downto 0);
signal vga_blue : std_logic_vector(3 downto 0);

-- RGB mapping function: returns 12-bit RGB (R[11:8], G[7:4], B[3:0])
function map_rgb(output_guess_in : in WORD; gray_in : in std_logic_vector(7 downto 0)) return std_logic_vector is
  variable rgb12 : std_logic_vector(11 downto 0) := (others => '0');
  variable g4 : std_logic_vector(3 downto 0) := gray_in(7 downto 4);
  variable idx : integer := to_integer(unsigned(output_guess_in));
begin
  case idx is
    when 8 =>
      -- Yellow scale: R and G follow grayscale, B = 0
      rgb12(11 downto 8) := g4; -- R
      rgb12(7 downto 4)  := g4; -- G
      rgb12(3 downto 0)  := (others => '0'); -- B
    when others =>
      -- Default: greyscale on all channels
      rgb12(11 downto 8) := g4; -- R
      rgb12(7 downto 4)  := g4; -- G
      rgb12(3 downto 0)  := g4; -- B
  end case;
  return rgb12;
end function;

signal rgb12_sig : std_logic_vector(11 downto 0) := (others => '0');

-- 28x28 image scaling signals
signal scaled_x : integer range 0 to IMAGE_WIDTH-1;
signal scaled_y : integer range 0 to IMAGE_HEIGHT-1;
signal pixel_in_image : std_logic;
signal grayscale_pixel : std_logic_vector(3 downto 0);  -- Convert 8-bit to 4-bit

-- Pipeline registers to match BRAM read latency
signal pixel_in_image_d1 : std_logic := '0';
signal pixel_in_image_d2 : std_logic := '0';
signal active_d1 : std_logic := '0';
signal active_d2 : std_logic := '0';


begin
  
  -- For simulation: bypass clock wizard and use system clock directly
  -- Comment out these direct assignments for synthesis:
  -- pxl_clk <= CLK_I;
  -- clk_locked <= not RST;  -- Locked when not in reset
  
  -- For synthesis (uncomment for real hardware):
  clk_div_inst : clk_wiz_0
    port map
     (-- Clock in ports
      clk_in1  => CLK_I,
      reset    => RST,
      clk_out1 => pxl_clk,
      locked   => clk_locked);

  -- Keep VGA logic in reset until pixel clock is stable
  pxl_clk_rst <= RST or not clk_locked;

  
  ----------------------------------------------------
  -------    28x28 IMAGE DISPLAY LOGIC         -------
  ----------------------------------------------------
  
  -- Memory address output to SPI controller: simple linear address from scaled coordinates
  -- Address = row * width + column
  -- Note: This crosses clock domains (pxl_clk -> system clk) but it's safe because
  -- addresses change slowly and SPI controller's dual-port BRAM is asynchronous read
  process(pxl_clk)
  begin
    if rising_edge(pxl_clk) then
      if pixel_in_image = '1' then
        spi_vga_addr <= std_logic_vector(to_unsigned(scaled_y * IMAGE_WIDTH + scaled_x, 10));
      else
        spi_vga_addr <= (others => '0');
      end if;
    end if;
  end process;
  
  -- Pipeline stages to match BRAM read latency (~2 cycles)
  -- This ensures spi_vga_data is valid when we use it
  process(pxl_clk)
  begin
    if rising_edge(pxl_clk) then
      -- Stage 1: Delay control signals
      pixel_in_image_d1 <= pixel_in_image;
      active_d1 <= active;
      
      -- Stage 2: Delay again to match BRAM output
      pixel_in_image_d2 <= pixel_in_image_d1;
      active_d2 <= active_d1;
    end if;
  end process;
  
  -- Convert 8-bit grayscale to 4-bit (take upper 4 bits)
  -- Now spi_vga_data has had 2 cycles to arrive from BRAM
  grayscale_pixel <= spi_vga_data(7 downto 4);
  
  -- Calculate which pixel of the 28x28 image we're displaying
  -- Divide screen position by scale factors to get image pixel coordinates
  process(pxl_clk)
  begin
    if rising_edge(pxl_clk) then
      if active = '1' then
        -- Calculate image pixel coordinates
        scaled_x <= (to_integer(unsigned(h_cntr_reg)) - OFFSET_X) / SCALE_X;
        scaled_y <= (to_integer(unsigned(v_cntr_reg)) - OFFSET_Y) / SCALE_Y;
        
        -- Check if current screen pixel is within the 28x28 image bounds
        if (h_cntr_reg >= OFFSET_X and h_cntr_reg < (OFFSET_X + IMAGE_WIDTH * SCALE_X) and
            v_cntr_reg >= OFFSET_Y and v_cntr_reg < (OFFSET_Y + IMAGE_HEIGHT * SCALE_Y)) then
          pixel_in_image <= '1';
        else
          pixel_in_image <= '0';
        end if;
      else
        pixel_in_image <= '0';
      end if;
    end if;
  end process;
  
  -- Generate memory address from scaled coordinates
  -- Address = row * width + column
  -- Map pixel to RGB using `map_rgb` and delayed control signals that match the BRAM data pipeline
  rgb12_sig <= map_rgb(output_guess, spi_vga_data) when (active_d2 = '1' and pixel_in_image_d2 = '1') else (others => '0');

  vga_red   <= rgb12_sig(11 downto 8);
  vga_green <= rgb12_sig(7 downto 4);
  vga_blue  <= rgb12_sig(3 downto 0);
  
  
 ------------------------------------------------------
 -------         SYNC GENERATION                 ------
 ------------------------------------------------------
 
  process (pxl_clk)
  begin
    if (rising_edge(pxl_clk)) then
      if (pxl_clk_rst = '1') then
        h_cntr_reg <= (others => '0');
      elsif (h_cntr_reg = (H_MAX - 1)) then
        h_cntr_reg <= (others =>'0');
      else
        h_cntr_reg <= h_cntr_reg + 1;
      end if;
    end if;
  end process;
  
  process (pxl_clk)
  begin
    if (rising_edge(pxl_clk)) then
      if (pxl_clk_rst = '1') then
        v_cntr_reg <= (others => '0');
      elsif ((h_cntr_reg = (H_MAX - 1)) and (v_cntr_reg = (V_MAX - 1))) then
        v_cntr_reg <= (others =>'0');
      elsif (h_cntr_reg = (H_MAX - 1)) then
        v_cntr_reg <= v_cntr_reg + 1;
      end if;
    end if;
  end process;
  
  process (pxl_clk)
  begin
    if (rising_edge(pxl_clk)) then
      if (h_cntr_reg >= (H_FP + FRAME_WIDTH - 1)) and (h_cntr_reg < (H_FP + FRAME_WIDTH + H_PW - 1)) then
        h_sync_reg <= H_POL;
      else
        h_sync_reg <= not(H_POL);
      end if;
    end if;
  end process;
  
  
  process (pxl_clk)
  begin
    if (rising_edge(pxl_clk)) then
      if (v_cntr_reg >= (V_FP + FRAME_HEIGHT - 1)) and (v_cntr_reg < (V_FP + FRAME_HEIGHT + V_PW - 1)) then
        v_sync_reg <= V_POL;
      else
        v_sync_reg <= not(V_POL);
      end if;
    end if;
  end process;
  
  
  active <= '1' when ((h_cntr_reg < FRAME_WIDTH) and (v_cntr_reg < FRAME_HEIGHT))else
            '0';

  -- Frame start pulse: asserted for one cycle at the beginning of each frame
  vga_frame_start <= '1' when (h_cntr_reg = 0 and v_cntr_reg = 0) else '0';

  process (pxl_clk)
  begin
    if (rising_edge(pxl_clk)) then
      v_sync_dly_reg <= v_sync_reg;
      h_sync_dly_reg <= h_sync_reg;
      vga_red_reg <= vga_red;
      vga_green_reg <= vga_green;
      vga_blue_reg <= vga_blue;
    end if;
  end process;

  VGA_HS_O <= h_sync_dly_reg;
  VGA_VS_O <= v_sync_dly_reg;
  VGA_R <= vga_red_reg;
  VGA_G <= vga_green_reg;
  VGA_B <= vga_blue_reg;

end Behavioral;