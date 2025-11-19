library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;                                                  -- For to_unsigned function
use work.types_pkg.all;


entity vga_top is
    Generic (
        IMAGE_WIDTH  : natural := 28;
        IMAGE_HEIGHT : natural := 28
    );
    Port ( CLK_I : in  STD_LOGIC;                                          -- 100 MHz system clock
           RST : in STD_LOGIC;                                             -- Reset
           
           -- VGA outputs
           VGA_HS_O : out  STD_LOGIC;
           VGA_VS_O : out  STD_LOGIC;
           VGA_R : out  STD_LOGIC_VECTOR (3 downto 0);
           VGA_B : out  STD_LOGIC_VECTOR (3 downto 0);
           VGA_G : out  STD_LOGIC_VECTOR (3 downto 0);
           
           -- Interface to SPI Memory Controller (port B - reads from busy buffer)
           spi_vga_addr : out STD_LOGIC_VECTOR (9 downto 0);              -- Address to SPI controller
           spi_vga_data : in  STD_LOGIC_VECTOR (7 downto 0);              -- Data from SPI controller
           vga_frame_start : out STD_LOGIC;                               -- Pulse at start of each frame

           output_guess : in WORD                                         -- CNN output guess to display
    );
end vga_top;

architecture Behavioral of vga_top is

component clk_wiz_0
port
 (
    clk_in1  : in  std_logic;                                             -- 100 MHz system clock
    reset    : in  std_logic;                                             -- Active high reset
    clk_out1 : out std_logic;                                             -- 25 MHz VGA pixel clock
    locked   : out std_logic                                              -- Clock stable indicator (optional
 );
end component;



constant FRAME_WIDTH : natural := 640;
constant FRAME_HEIGHT : natural := 480;
constant H_FP : natural := 16;                                            --H front porch width (pixels)
constant H_PW : natural := 96;                                            --H sync pulse width (pixels)
constant H_MAX : natural := 800;                                          --H total period (pixels)
constant V_FP : natural := 10;                                            --V front porch width (lines)
constant V_PW : natural := 2;                                             --V sync pulse width (lines)
constant V_MAX : natural := 525;                                          --V total period (lines)


constant H_POL : std_logic := '0';                                        --H sync polarity                 
constant V_POL : std_logic := '0';                                        --V sync polarity      

-- Image Display Constants (from generics)
-- SCALE_X/Y calculated to fit image to screen
constant SCALE_X : natural := FRAME_WIDTH / IMAGE_WIDTH;                   -- Pixels per image pixel horizontally
constant SCALE_Y : natural := FRAME_HEIGHT / IMAGE_HEIGHT;                 -- Pixels per image pixel vertically
constant OFFSET_X : natural := (FRAME_WIDTH - IMAGE_WIDTH * SCALE_X) / 2;  -- Center horizontally
constant OFFSET_Y : natural := (FRAME_HEIGHT - IMAGE_HEIGHT * SCALE_Y) / 2;-- Center vertically

signal pxl_clk : std_logic;
signal clk_locked : std_logic;
signal pxl_clk_rst : std_logic;                                           -- Gated reset for pixel clock domain
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
  
  -- Clock Wizard Instance
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
      
      pixel_in_image_d1 <= pixel_in_image;                          -- Stage 1: Delay control signals
      active_d1 <= active;
      
      
      pixel_in_image_d2 <= pixel_in_image_d1;                       -- Stage 2: Delay again to match BRAM output
      active_d2 <= active_d1;
    end if;
  end process;
  


  grayscale_pixel <= spi_vga_data(7 downto 4);                        -- Convert 8-bit grayscale to 4-bit (take upper 4 bits)            
  
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
  


  vga_red   <= grayscale_pixel when (active_d2 = '1' and pixel_in_image_d2 = '1') else (others => '0');
  vga_green <= grayscale_pixel when (active_d2 = '1' and pixel_in_image_d2 = '1') else (others => '0');
  vga_blue  <= grayscale_pixel when (active_d2 = '1' and pixel_in_image_d2 = '1') else (others => '0');
  
  
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