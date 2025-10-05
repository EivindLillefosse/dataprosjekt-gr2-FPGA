----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: 
-- 
-- Create Date: 05.10.2025
-- Module Name: fully_connected_tb - Behavioral
-- Project Name: CNN Accelerator
-- Description: Testbench for fully connected layer (9 inputs → 4 outputs)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity fully_connected_tb is
end fully_connected_tb;

architecture Behavioral of fully_connected_tb is
    
    component fully_connected is
        generic (
            NUM_INPUTS  : integer := 9;
            NUM_OUTPUTS : integer := 4
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
    end component;
    
    constant NUM_INPUTS  : integer := 9;
    constant NUM_OUTPUTS : integer := 4;
    constant CLK_PERIOD  : time := 10 ns;
    
    signal clk   : std_logic := '0';
    signal rst   : std_logic := '0';
    signal enable : std_logic := '0';
    
    signal input_valid : std_logic := '0';
    signal input_pixel : WORD := (others => '0');
    signal input_ready : std_logic;
    
    signal output_valid : std_logic;
    signal output_pixel : WORD;
    signal output_index : integer range 0 to NUM_OUTPUTS-1;
    signal output_ready : std_logic := '1';
    
    signal layer_done : std_logic;
    
    -- Test data: inputs = [1,2,3,4,5,6,7,8,9]
    type input_array_type is array (0 to NUM_INPUTS-1) of integer;
    constant test_inputs : input_array_type := (1, 2, 3, 4, 5, 6, 7, 8, 9);
    
    -- Weights: 9×4 = 36 weights in row-major order
    -- Neuron 0: [1,0,0,0,1,0,2,0,0] → 1*1 + 5*1 + 7*2 = 20
    -- Neuron 1: [0,1,0,0,1,0,0,2,0] → 2*1 + 5*1 + 8*2 = 23
    -- Neuron 2: [0,0,1,0,1,0,0,0,2] → 3*1 + 5*1 + 9*2 = 26
    -- Neuron 3: [0,0,0,1,1,0,0,0,0] → 4*1 + 5*1 = 9
    type weight_matrix_type is array (0 to NUM_INPUTS*NUM_OUTPUTS-1) of integer;
    constant test_weights : weight_matrix_type := (
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
        1, 1, 1, 1,
        0, 0, 0, 0,
        2, 0, 0, 0,
        0, 2, 0, 0,
        0, 0, 2, 0
    );
    
    type bias_array_type is array (0 to NUM_OUTPUTS-1) of integer;
    constant test_biases : bias_array_type := (10, 20, 30, 40);
    
    -- Expected outputs:
    -- Output[0] = (1*1 + 5*1 + 7*2) + 10 = 30
    -- Output[1] = (2*1 + 5*1 + 8*2) + 20 = 43
    -- Output[2] = (3*1 + 5*1 + 9*2) + 30 = 56
    -- Output[3] = (4*1 + 5*1) + 40 = 49
    constant expected_outputs : bias_array_type := (30, 43, 56, 49);
    
    signal test_done : boolean := false;
    signal weight_addr_internal : std_logic_vector(15 downto 0);
    signal bias_addr_internal : std_logic_vector(7 downto 0);
    
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

begin

    -- Clock generation
    clk_process : process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;
    
    -- Dummy weight ROM (behavioral simulation)
    weight_rom_process : process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            addr_int := to_integer(unsigned(weight_addr_internal));
            if addr_int < NUM_INPUTS * NUM_OUTPUTS then
                -- Simulate ROM behavior
            end if;
        end if;
    end process;
    
    
    -- Dummy bias ROM (behavioral simulation)
    bias_rom_process : process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            addr_int := to_integer(unsigned(bias_addr_internal));
            if addr_int < NUM_OUTPUTS then
                -- Simulate ROM behavior
            end if;
        end if;
    end process;
    
    -- DUT instantiation
    DUT : fully_connected
        generic map (
            NUM_INPUTS  => NUM_INPUTS,
            NUM_OUTPUTS => NUM_OUTPUTS
        )
        port map (
            clk          => clk,
            rst          => rst,
            enable       => enable,
            input_valid  => input_valid,
            input_pixel  => input_pixel,
            input_ready  => input_ready,
            output_valid => output_valid,
            output_pixel => output_pixel,
            output_index => output_index,
            output_ready => output_ready,
            layer_done   => layer_done
        );
    
    -- Stimulus process
    stim_process : process
    begin
        report "========================================";
        report "Starting Fully Connected Layer Testbench";
        report "========================================";
        report "Configuration:";
        report "  NUM_INPUTS  = " & integer'image(NUM_INPUTS);
        report "  NUM_OUTPUTS = " & integer'image(NUM_OUTPUTS);
        report "----------------------------------------";
        
        rst <= '1';
        enable <= '0';
        input_valid <= '0';
        output_ready <= '1';
        wait for CLK_PERIOD * 4;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        report "Enabling layer...";
        enable <= '1';
        wait for CLK_PERIOD;
        enable <= '0';
        
        report "Streaming input pixels...";
        report "Test inputs: 1, 2, 3, 4, 5, 6, 7, 8, 9";
        
        for i in 0 to NUM_INPUTS-1 loop
            wait until input_ready = '1';
            wait for CLK_PERIOD;
            
            input_pixel <= std_logic_vector(to_signed(test_inputs(i), 8));
            input_valid <= '1';
            
            report "  Sent input[" & integer'image(i) & "] = " & integer'image(test_inputs(i));
            
            wait for CLK_PERIOD;
            input_valid <= '0';
        end loop;
        
        report "All input pixels sent.";
        report "Waiting for outputs...";
        
        for i in 0 to NUM_OUTPUTS-1 loop
            wait until output_valid = '1';
            
            report "  Output[" & integer'image(output_index) & "] = " & 
                   integer'image(to_integer(signed(output_pixel))) &
                   "  (expected: " & integer'image(expected_outputs(output_index)) & ")";
            
            if to_integer(signed(output_pixel)) = expected_outputs(output_index) then
                report "    ✓ CORRECT";
            else
                report "    ✗ ERROR: Mismatch!" severity error;
            end if;
            
            wait for CLK_PERIOD;
        end loop;
        
        wait until layer_done = '1';
        report "Layer processing complete.";
        
        wait for CLK_PERIOD * 10;
        
        report "========================================";
        report "Test Complete";
        report "========================================";
        report "Expected outputs:";
        report "  Output[0] = " & integer'image(expected_outputs(0)) & " (calculation: 1*1 + 5*1 + 7*2 + 10)";
        report "  Output[1] = " & integer'image(expected_outputs(1)) & " (calculation: 2*1 + 5*1 + 8*2 + 20)";
        report "  Output[2] = " & integer'image(expected_outputs(2)) & " (calculation: 3*1 + 5*1 + 9*2 + 30)";
        report "  Output[3] = " & integer'image(expected_outputs(3)) & " (calculation: 4*1 + 5*1 + 40)";
        report "========================================";
        
        test_done <= true;
        wait;
    end process;
    
    -- Monitor process
    monitor_process : process(clk)
    begin
        if rising_edge(clk) then
            if input_ready = '1' and input_valid = '1' then
                report "    → Input accepted: " & integer'image(to_integer(signed(input_pixel)));
            end if;
            
            if output_valid = '1' and output_ready = '1' then
                report "    ← Output[" & integer'image(output_index) & "] sent: " & 
                       integer'image(to_integer(signed(output_pixel)));
            end if;
        end if;
    end process;

end Behavioral;
