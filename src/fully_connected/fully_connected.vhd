----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 05.10.2025
-- Module Name: fully_connected - Behavioral
-- Project Name: CNN Accelerator
-- Description: Streaming fully connected layer with MAC-based accumulation
-- 
-- Dependencies: types_pkg, MAC, weight/bias ROM
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fully_connected is
    generic (
        NUM_INPUTS  : integer := 400;  
        NUM_OUTPUTS : integer := 64
    );
    Port ( 
        clk   : in STD_LOGIC;
        rst   : in STD_LOGIC;
        enable : in STD_LOGIC;
        input_valid : in  std_logic;
        input_pixel : in  WORD;
        input_ready : out std_logic;
        output_valid : out std_logic;
        output_pixel : out WORD;
        output_index : out integer range 0 to NUM_OUTPUTS-1;
        output_ready : in  std_logic;
        layer_done : out STD_LOGIC
    );
end fully_connected;

architecture Behavioral of fully_connected is
    
    COMPONENT fc_mem_weights
    PORT (
        clka  : IN  STD_LOGIC;
        ena   : IN  STD_LOGIC;
        addra : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
        douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
    END COMPONENT;
    
    COMPONENT fc_mem_bias
    PORT (
        clka  : IN  STD_LOGIC;
        ena   : IN  STD_LOGIC;
        addra : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
        douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
    END COMPONENT;
    
    COMPONENT MAC
    PORT (
        clk      : IN  STD_LOGIC;
        rst      : IN  STD_LOGIC;
        pixel_in : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
        weights  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
        valid    : IN  STD_LOGIC;
        clear    : IN  STD_LOGIC;
        result   : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        done     : OUT STD_LOGIC
    );
    END COMPONENT;
    
    type state_type is (
        IDLE, PROCESS_NEURON, WAIT_MAC, NEXT_NEURON, ADD_BIAS, OUTPUT_RESULT, FINISH
    );
    signal current_state : state_type := IDLE;
    
    signal weight_addr : std_logic_vector(15 downto 0) := (others => '0');
    signal weight_data : std_logic_vector(7 downto 0);
    signal weight_en   : std_logic := '0';
    
    signal bias_addr : std_logic_vector(7 downto 0) := (others => '0');
    signal bias_data : std_logic_vector(7 downto 0);
    signal bias_en   : std_logic := '0';
    
    type result_array is array (0 to NUM_OUTPUTS-1) of std_logic_vector(15 downto 0);
    signal neuron_results : result_array := (others => (others => '0'));
    
    signal mac_pixel_in : std_logic_vector(7 downto 0);
    signal mac_weight   : std_logic_vector(7 downto 0);
    signal mac_valid    : std_logic := '0';
    signal mac_clear    : std_logic := '0';
    signal mac_result   : std_logic_vector(15 downto 0);
    signal mac_done     : std_logic;
    
    signal weight_signed : signed(7 downto 0);
    signal bias_signed   : signed(7 downto 0);
    signal mac_result_signed : signed(15 downto 0);
    
    signal input_count   : integer range 0 to NUM_INPUTS := 0;
    signal neuron_index  : integer range 0 to NUM_OUTPUTS-1 := 0;
    signal output_count  : integer range 0 to NUM_OUTPUTS := 0;
    
    signal wait_cycles : integer range 0 to 3 := 0;
    
    signal temp_result : signed(23 downto 0);
    signal output_temp : WORD;
    
    type pixel_buffer_type is array (0 to NUM_INPUTS-1) of WORD;
    signal pixel_buffer : pixel_buffer_type := (others => (others => '0'));
    signal pixel_buffer_valid : std_logic := '0';

begin

    weight_mem_inst : fc_mem_weights
    PORT MAP (
        clka  => clk,
        ena   => weight_en,
        addra => weight_addr,
        douta => weight_data
    );
    
    bias_mem_inst : fc_mem_bias
    PORT MAP (
        clka  => clk,
        ena   => bias_en,
        addra => bias_addr,
        douta => bias_data
    );
    
    mac_inst : MAC
    PORT MAP (
        clk      => clk,
        rst      => rst,
        pixel_in => mac_pixel_in,
        weights  => mac_weight,
        valid    => mac_valid,
        clear    => mac_clear,
        result   => mac_result,
        done     => mac_done
    );
    
    weight_signed <= signed(weight_data);
    bias_signed   <= signed(bias_data);
    mac_result_signed <= signed(mac_result);
    
    FSM_process: process(clk, rst)
        variable input_idx : integer range 0 to NUM_INPUTS-1 := 0;
    begin
        if rst = '1' then
            current_state <= IDLE;
            input_ready <= '0';
            output_valid <= '0';
            layer_done <= '0';
            weight_en <= '0';
            bias_en <= '0';
            input_count <= 0;
            neuron_index <= 0;
            output_count <= 0;
            wait_cycles <= 0;
            neuron_results <= (others => (others => '0'));
            weight_addr <= (others => '0');
            bias_addr <= (others => '0');
            output_pixel <= (others => '0');
            output_index <= 0;
            mac_valid <= '0';
            mac_clear <= '0';
            mac_pixel_in <= (others => '0');
            mac_weight <= (others => '0');
            pixel_buffer <= (others => (others => '0'));
            pixel_buffer_valid <= '0';
            input_idx := 0;
            
        elsif rising_edge(clk) then
            case current_state is
                
                when IDLE =>
                    layer_done <= '0';
                    output_valid <= '0';
                    mac_valid <= '0';
                    mac_clear <= '0';
                    weight_en <= '0';
                    bias_en <= '0';
                    
                    if enable = '1' then
                        input_count <= 0;
                        neuron_index <= 0;
                        output_count <= 0;
                        neuron_results <= (others => (others => '0'));
                        pixel_buffer_valid <= '0';
                        input_idx := 0;
                        input_ready <= '1';
                    elsif input_ready = '1' and input_valid = '1' then
                        pixel_buffer(input_idx) <= input_pixel;
                        input_idx := input_idx + 1;
                        
                        if input_idx >= NUM_INPUTS - 1 then
                            pixel_buffer_valid <= '1';
                            input_ready <= '0';
                            input_idx := 0;
                            current_state <= PROCESS_NEURON;
                        end if;
                    end if;
                
                when PROCESS_NEURON =>
                    if input_count = 0 then
                        mac_clear <= '1';
                        wait_cycles <= 0;
                    elsif wait_cycles < 2 then
                        mac_clear <= '0';
                        wait_cycles <= wait_cycles + 1;
                    else
                        mac_clear <= '0';
                        weight_addr <= std_logic_vector(to_unsigned(
                            input_count * NUM_OUTPUTS + neuron_index, 16));
                        weight_en <= '1';
                        wait_cycles <= 0;
                        
                        if wait_cycles >= 2 then
                            weight_en <= '0';
                            mac_pixel_in <= pixel_buffer(input_count);
                            mac_weight <= weight_data;
                            mac_valid <= '1';
                            
                            if input_count < NUM_INPUTS - 1 then
                                input_count <= input_count + 1;
                                wait_cycles <= 0;
                            else
                                mac_valid <= '0';
                                current_state <= WAIT_MAC;
                            end if;
                        else
                            wait_cycles <= wait_cycles + 1;
                        end if;
                    end if;
                
                when WAIT_MAC =>
                    mac_valid <= '0';
                    
                    if mac_done = '1' then
                        neuron_results(neuron_index) <= mac_result;
                        current_state <= NEXT_NEURON;
                    end if;
                
                when NEXT_NEURON =>
                    input_count <= 0;
                    
                    if neuron_index < NUM_OUTPUTS - 1 then
                        neuron_index <= neuron_index + 1;
                        current_state <= PROCESS_NEURON;
                    else
                        neuron_index <= 0;
                        output_count <= 0;
                        current_state <= ADD_BIAS;
                    end if;
                
                when ADD_BIAS =>
                    bias_addr <= std_logic_vector(to_unsigned(output_count, 8));
                    bias_en <= '1';
                    wait_cycles <= 0;
                    current_state <= OUTPUT_RESULT;
                
                when OUTPUT_RESULT =>
                    wait_cycles <= wait_cycles + 1;
                    
                    if wait_cycles >= 2 then
                        bias_en <= '0';
                        temp_result <= resize(mac_result_signed, 24) + resize(bias_signed, 24);
                        
                        if temp_result(23) = '1' then
                            output_temp <= (others => '0');
                        else
                            if temp_result > 127 then
                                output_temp <= std_logic_vector(to_signed(127, 8));
                            else
                                output_temp <= std_logic_vector(resize(temp_result, 8));
                            end if;
                        end if;
                        
                        if output_ready = '1' then
                            output_pixel <= output_temp;
                            output_index <= output_count;
                            output_valid <= '1';
                            
                            if output_count < NUM_OUTPUTS - 1 then
                                output_count <= output_count + 1;
                                wait_cycles <= 0;
                                current_state <= ADD_BIAS;
                            else
                                current_state <= FINISH;
                            end if;
                        end if;
                    end if;
                
                when FINISH =>
                    output_valid <= '0';
                    layer_done <= '1';
                    input_ready <= '1';
                    current_state <= IDLE;
                
                when others =>
                    current_state <= IDLE;
                    
            end case;
        end if;
    end process;

end Behavioral;
