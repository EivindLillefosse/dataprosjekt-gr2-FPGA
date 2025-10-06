----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Nikolai Nore
-- 
-- Create Date: 06.10.2025
-- Design Name: Fully_Connected
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
-- Tool Versions: 
-- Description: 
-- 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

Library UNISIM;
use UNISIM.vcomponents.all;

Library UNIMACRO;
use UNIMACRO.vcomponents.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Fully_Connected is
   generic (
        NUM_FILTERS : integer := 64
   );
   Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        enable : in STD_LOGIC;

        output_valid : out std_logic; -- High when output_pixel is valid
        output_pixel : out WORD_ARRAY_16(0 to NUM_FILTERS-1); -- 16-bit output pixel
        input_row : in integer; -- Current row of the output pixel
        input_col : in integer; -- Current column of the output pixel
        input_ready : in std_logic; -- High when ready for the next output
        input_channel : in integer; -- Current channel of the output pixel
        layer_done : out STD_LOGIC
       );
end Fully_Connected;

architecture Behavioral of Fully_Connected is

    -- Use your existing weight memory controller
    component weight_memory_controller is
        generic (
            NUM_FILTERS : integer := 8;
            KERNEL_SIZE : integer := 3;
            ADDR_WIDTH  : integer := 7
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            load_req    : in  std_logic;
            filter_idx  : in  integer range 0 to NUM_FILTERS-1;
            kernel_row  : in  integer range 0 to KERNEL_SIZE-1;
            kernel_col  : in  integer range 0 to KERNEL_SIZE-1;
            weight_data : out std_logic_vector(7 downto 0);
            data_valid  : out std_logic;
            load_done   : out std_logic
        );
    end component;

    -- MAC component (reuse from convolution layer)
    component MAC is
        generic (
            width_a : integer := 8;
            width_b : integer := 8;
            width_p : integer := 16
        );
        Port (
            clk      : in  STD_LOGIC;
            rst      : in  STD_LOGIC;
            pixel_in : in  STD_LOGIC_VECTOR (7 downto 0);
            weights  : in  STD_LOGIC_VECTOR (7 downto 0);
            valid    : in  STD_LOGIC;
            clear    : in  STD_LOGIC;
            result   : out STD_LOGIC_VECTOR (15 downto 0);
            done     : out STD_LOGIC  
        );
    end component;

    -- Weight controller signals
    signal weight_load_req : std_logic := '0';
    signal weight_filter_idx : integer range 0 to NUM_FILTERS-1 := 0;
    signal weight_data : std_logic_vector(7 downto 0);
    signal weight_valid : std_logic;
    signal weight_done : std_logic;

    -- MAC array signals
    signal pixel_input : std_logic_vector(7 downto 0);  -- Current pixel value
    signal mac_weights : WORD_ARRAY(0 to NUM_FILTERS-1); -- Weights for each MAC
    signal mac_valid : std_logic := '0';  -- Enable MAC computation
    signal mac_clear : std_logic := '0';  -- Clear MAC accumulators
    signal mac_results : WORD_ARRAY_16(0 to NUM_FILTERS-1);  -- MAC results
    signal mac_done : std_logic_vector(NUM_FILTERS-1 downto 0);  -- MAC done flags

begin

    -- Instantiate the weight memory controller
    weight_ctrl_inst : weight_memory_controller
        generic map (
            NUM_FILTERS => NUM_FILTERS,
            KERNEL_SIZE => 3,  -- Adjust if needed
            ADDR_WIDTH  => 7   -- Adjust based on your memory size
        )
        port map (
            clk         => clk,
            rst         => rst,
            load_req    => weight_load_req,
            filter_idx  => weight_filter_idx,
            kernel_row  => input_row,      -- Use your input_row
            kernel_col  => input_col,      -- Use your input_col  
            weight_data => weight_data,
            data_valid  => weight_valid,
            load_done   => weight_done
        );

    -- Generate 64 MAC instances (one for each output neuron)
    mac_gen : for i in 0 to NUM_FILTERS-1 generate
        mac_inst : MAC
            generic map (
                width_a => 8,   -- 8-bit input pixels
                width_b => 8,   -- 8-bit weights  
                width_p => 16   -- 16-bit results
            )
            port map (
                clk      => clk,
                rst      => rst,
                pixel_in => pixel_input,
                weights  => mac_weights(i),
                valid    => mac_valid,
                clear    => mac_clear,
                result   => mac_results(i),
                done     => mac_done(i)
            );
    end generate;

    -- Connect MAC results to output
    output_pixel <= mac_results;
    output_valid <= mac_done(0); -- Or use AND of all mac_done signals if needed

    -- Weight management process
    -- This process loads weights for each MAC when a new pixel arrives
    weight_mgmt_proc: process(clk, rst)
        variable current_mac : integer range 0 to NUM_FILTERS-1 := 0;
        type weight_state_type is (IDLE, LOAD_WEIGHTS, COMPUTE);
        variable state : weight_state_type := IDLE;
    begin
        if rst = '1' then
            weight_load_req <= '0';
            weight_filter_idx <= 0;
            mac_valid <= '0';
            current_mac := 0;
            state := IDLE;
            
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    if input_ready = '1' then
                        -- New pixel received, start loading weights for all MACs
                        pixel_input <= "00000000"; -- Set this to your actual pixel value
                        current_mac := 0;
                        state := LOAD_WEIGHTS;
                    end if;
                    
                when LOAD_WEIGHTS =>
                    -- Load weight for current MAC
                    weight_filter_idx <= current_mac;
                    weight_load_req <= '1';
                    
                    if weight_done = '1' then
                        mac_weights(current_mac) <= weight_data;
                        weight_load_req <= '0';
                        
                        if current_mac = NUM_FILTERS-1 then
                            -- All weights loaded, start computation
                            mac_valid <= '1';
                            state := COMPUTE;
                        else
                            current_mac := current_mac + 1;
                        end if;
                    end if;
                    
                when COMPUTE =>
                    mac_valid <= '0';  -- Single cycle compute enable
                    state := IDLE;
                    
                when others =>
                    state := IDLE;
            end case;
        end if;
    end process;

end Behavioral;

