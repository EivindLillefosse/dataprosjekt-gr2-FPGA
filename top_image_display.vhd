----------------------------------------------------------------------------------
-- Modified VGA Image Display from Block RAM
-- Based on Digilent Arty VGA example
-- Modified to display image from Block RAM memory
----------------------------------------------------------------------------------   
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    Port ( CLK_I : in  STD_LOGIC;
           VGA_HS_O : out  STD_LOGIC;
           VGA_VS_O : out  STD_LOGIC;
           VGA_R : out  STD_LOGIC_VECTOR (3 downto 0);
           VGA_B : out  STD_LOGIC_VECTOR (3 downto 0);
           VGA_G : out  STD_LOGIC_VECTOR (3 downto 0));
end top;

architecture Behavioral of top is

component clk_wiz_0
port
 (-- Clock in ports
  CLK_IN1           : in     std_logic;
  -- Clock out ports
  CLK_OUT1          : out    std_logic
 );
end component;

-- Block RAM component for image storage
component image_ram
  port (
    clka : in std_logic;
    addra : in std_logic_vector(18 downto 0);  -- Adjust based on image size
    douta : out std_logic_vector(11 downto 0)  -- 12-bit RGB output
  );
end component;

-- VGA Timing constants - Using 640x480@60Hz for practical image display
-- (1920x1080 requires too much memory for most images)
constant FRAME_WIDTH : natural := 640;
constant FRAME_HEIGHT : natural := 480;

constant H_FP : natural := 16;   -- H front porch width (pixels)
constant H_PW : natural := 96;   -- H sync pulse width (pixels)
constant H_MAX : natural := 800; -- H total period (pixels)

constant V_FP : natural := 10;   -- V front porch width (lines)
constant V_PW : natural := 2;    -- V sync pulse width (lines)
constant V_MAX : natural := 525; -- V total period (lines)

constant H_POL : std_logic := '0';
constant V_POL : std_logic := '0';

-- Image display constants
-- Adjust these to match your image resolution
constant IMAGE_WIDTH : natural := 640;
constant IMAGE_HEIGHT : natural := 480;

-- Position image on screen (centered or top-left)
constant IMAGE_X_OFFSET : natural := (FRAME_WIDTH - IMAGE_WIDTH) / 2;
constant IMAGE_Y_OFFSET : natural := (FRAME_HEIGHT - IMAGE_HEIGHT) / 2;

signal pxl_clk : std_logic;
signal active : std_logic;

signal h_cntr_reg : std_logic_vector(11 downto 0) := (others =>'0');
signal v_cntr_reg : std_logic_vector(11 downto 0) := (others =>'0');

signal h_sync_reg : std_logic := not(H_POL);
signal v_sync_reg : std_logic := not(V_POL);

signal h_sync_dly_reg : std_logic := not(H_POL);
signal v_sync_dly_reg : std_logic := not(V_POL);

signal vga_red_reg : std_logic_vector(3 downto 0) := (others =>'0');
signal vga_green_reg : std_logic_vector(3 downto 0) := (others =>'0');
signal vga_blue_reg : std_logic_vector(3 downto 0) := (others =>'0');

signal vga_red : std_logic_vector(3 downto 0);
signal vga_green : std_logic_vector(3 downto 0);
signal vga_blue : std_logic_vector(3 downto 0);

-- Image RAM signals
signal ram_addr : std_logic_vector(18 downto 0);  -- Up to 512K addresses
signal ram_data : std_logic_vector(11 downto 0);  -- 12-bit RGB
signal image_active : std_logic;
signal image_x : unsigned(11 downto 0);
signal image_y : unsigned(11 downto 0);

begin

clk_div_inst : clk_wiz_0
  port map
   (-- Clock in ports
    CLK_IN1 => CLK_I,
    -- Clock out ports
    CLK_OUT1 => pxl_clk);

-- Image RAM instance
-- NOTE: You need to create this IP in Vivado:
-- 1. Tools -> Create and Package IP -> Block Memory Generator
-- 2. Memory Type: Single Port ROM
-- 3. Port A Width: 12 bits
-- 4. Port A Depth: IMAGE_WIDTH * IMAGE_HEIGHT (e.g., 307200 for 640x480)
-- 5. Load Init File: Select your .coe file
-- 6. Generate
image_memory : image_ram
  port map (
    clka => pxl_clk,
    addra => ram_addr,
    douta => ram_data
  );

------------------------------------------------------
-------      IMAGE DISPLAY LOGIC              -------
------------------------------------------------------

-- Determine if current pixel is within image bounds
image_active <= '1' when (active = '1' and 
                          h_cntr_reg >= IMAGE_X_OFFSET and 
                          h_cntr_reg < (IMAGE_X_OFFSET + IMAGE_WIDTH) and
                          v_cntr_reg >= IMAGE_Y_OFFSET and
                          v_cntr_reg < (IMAGE_Y_OFFSET + IMAGE_HEIGHT))
                else '0';

-- Calculate position within image
image_x <= to_unsigned(to_integer(unsigned(h_cntr_reg)) - IMAGE_X_OFFSET, 12) 
           when image_active = '1' else (others => '0');
image_y <= to_unsigned(to_integer(unsigned(v_cntr_reg)) - IMAGE_Y_OFFSET, 12) 
           when image_active = '1' else (others => '0');

-- Calculate RAM address (row-major format: address = y * width + x)
-- We need to compute this one clock cycle ahead for RAM latency
process(pxl_clk)
  variable next_x : unsigned(11 downto 0);
  variable next_y : unsigned(11 downto 0);
  variable addr : unsigned(18 downto 0);
begin
  if rising_edge(pxl_clk) then
    -- Look ahead one pixel for RAM read latency
    if h_cntr_reg < (H_MAX - 1) then
      next_x := to_unsigned(to_integer(unsigned(h_cntr_reg)) + 1 - IMAGE_X_OFFSET, 12);
    else
      next_x := (others => '0');
    end if;
    
    next_y := to_unsigned(to_integer(unsigned(v_cntr_reg)) - IMAGE_Y_OFFSET, 12);
    
    -- Calculate address
    if (next_x < IMAGE_WIDTH and next_y < IMAGE_HEIGHT) then
      addr := next_y * to_unsigned(IMAGE_WIDTH, 12) + next_x;
      ram_addr <= std_logic_vector(addr(18 downto 0));
    else
      ram_addr <= (others => '0');
    end if;
  end if;
end process;

-- Output color from RAM when displaying image, otherwise black
vga_red   <= ram_data(11 downto 8) when image_active = '1' else (others => '0');
vga_green <= ram_data(7 downto 4)  when image_active = '1' else (others => '0');
vga_blue  <= ram_data(3 downto 0)  when image_active = '1' else (others => '0');

------------------------------------------------------
-------         SYNC GENERATION                 ------
------------------------------------------------------

process (pxl_clk)
begin
  if (rising_edge(pxl_clk)) then
    if (h_cntr_reg = (H_MAX - 1)) then
      h_cntr_reg <= (others =>'0');
    else
      h_cntr_reg <= std_logic_vector(unsigned(h_cntr_reg) + 1);
    end if;
  end if;
end process;

process (pxl_clk)
begin
  if (rising_edge(pxl_clk)) then
    if ((h_cntr_reg = std_logic_vector(to_unsigned(H_MAX - 1, 12))) and 
        (v_cntr_reg = std_logic_vector(to_unsigned(V_MAX - 1, 12)))) then
      v_cntr_reg <= (others =>'0');
    elsif (h_cntr_reg = std_logic_vector(to_unsigned(H_MAX - 1, 12))) then
      v_cntr_reg <= std_logic_vector(unsigned(v_cntr_reg) + 1);
    end if;
  end if;
end process;

process (pxl_clk)
begin
  if (rising_edge(pxl_clk)) then
    if (unsigned(h_cntr_reg) >= (H_FP + FRAME_WIDTH - 1)) and 
       (unsigned(h_cntr_reg) < (H_FP + FRAME_WIDTH + H_PW - 1)) then
      h_sync_reg <= H_POL;
    else
      h_sync_reg <= not(H_POL);
    end if;
  end if;
end process;

process (pxl_clk)
begin
  if (rising_edge(pxl_clk)) then
    if (unsigned(v_cntr_reg) >= (V_FP + FRAME_HEIGHT - 1)) and 
       (unsigned(v_cntr_reg) < (V_FP + FRAME_HEIGHT + V_PW - 1)) then
      v_sync_reg <= V_POL;
    else
      v_sync_reg <= not(V_POL);
    end if;
  end if;
end process;

active <= '1' when (unsigned(h_cntr_reg) < FRAME_WIDTH) and 
                    (unsigned(v_cntr_reg) < FRAME_HEIGHT) else '0';

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
