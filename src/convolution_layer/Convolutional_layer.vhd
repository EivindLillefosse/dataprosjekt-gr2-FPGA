----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 14.09.2025 15:20:31
-- Design Name: Multiplier
-- Module Name: top - Behavioral
-- Project Name: CNN Accelerator
-- Target Devices: Xilinx FPGA
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
use work.types_pkg.all;



entity conv_layer is
    generic (
        IMAGE_SIZE : integer := 28;
        KERNEL_SIZE : integer := 3;
        INPUT_CHANNELS : integer := 1;
        NUM_FILTERS : integer := 8;
        STRIDE : integer := 1
    );
    Port ( 
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        enable : in STD_LOGIC;
        input_data : in OUTPUT_ARRAY_VECTOR(0 to INPUT_CHANNELS-1,
                                              0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                              0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1);
        output_data : out OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1,
                                              0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                              0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1);
        done : out STD_LOGIC
    );
end conv_layer;

architecture Behavioral of conv_layer is
    -- Declare signals
    input_pixel  : WORD := (others => '0');
    signal weight_array : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1,
                                              0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                              0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1);

    signal weights : array (0 to NUM_FILTERS-1) of WORD := (others => (others => '0'));
    signal valid  : std_logic := '0';
    signal result_array  : OUTPUT_ARRAY_VECTOR(0 to NUM_FILTERS-1, 
                                         0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1, 
                                         0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE)+1);
    signal result : array (0 to NUM_FILTERS-1) of WORD := (others => (others => '0'));

begin
    -- Generate MAC instances
    mac_gen : for i in 0 to NUM_FILTERS-1 generate
        mac_inst : entity work.MAC
            generic map (
                width_a => 8,
                width_b => 8,
                width_p => 16
            )
            port map (
                clk     => clk,
                rst     => rst,
                pixel_in  => input_pixel,
                weights => weights(i),
                valid   => valid,
                result  => result(i)
            );
    end generate;
    -- Additional logic to handle input_data, weight_array, valid signal, and output_data

    process(clk, rst)
    begin
        if rst = '1' then
            valid <= '0';
            done <= '0';
            output_data <= (others => (others => (others => (others => '0'))));
        elsif rising_edge(clk) then
            if enable = '1' then
                for c in 0 to NUM_FILTERS-1 loop
                    for row in 0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE) loop
                        for col in 0 to ((IMAGE_SIZE-KERNEL_SIZE)/STRIDE) loop
                            for f in 0 to NUM_FILTERS-1 loop
                                weights(f) <= input_data(f, row, col);
                            end loop;
                            input_pixel <= input_data(c, row, col);
                            valid <= '1';
                            -- Wait for MAC to process
                            
                        end loop;
                    end loop;
                end loop;


                
                -- After processing all pixels
                done <= '1';
                output_data <= result_array; -- Assign the computed results to output_data
            else
                valid <= '0';
                done <= '0';
            end if;
        end if;
    end process;
end Behavioral;

