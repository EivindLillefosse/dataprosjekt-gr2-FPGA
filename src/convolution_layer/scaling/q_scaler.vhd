----------------------------------------------------------------------------------
-- Company: NTNU
-- Engineer: Eivind Lillefosse
-- 
-- Create Date: 10.13.2025
-- Design Name: Q-Format Scaler
-- Module Name: q_scaler - Behavioral
-- Project Name: CNN Accelerator
-- Description: Scales Q2.12 format to Q1.6 format with rounding and saturation
--              Input:  16-bit signed Q2.12 (2 integer bits, 12 fractional bits)
--              Output: 8-bit signed Q1.6 (1 sign + 1 integer bit, 6 fractional bits)
--              Operation: Right shift by 6 with rounding, then saturate to 8-bit range
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity q_scaler is
    generic (
        NUM_CHANNELS : integer := 8;        -- Number of parallel channels to scale
        INPUT_WIDTH  : integer := 16;       -- Q2.12 width
        OUTPUT_WIDTH : integer := 8;        -- Q1.6 width
        SHIFT_AMOUNT : integer := 6;        -- Bits to shift (12 - 6 = 6)
        SKIP_SHIFT   : boolean := TRUE     -- If true, bypass rounding and right shift (pass-through)
    );
    Port (
        clk        : in STD_LOGIC;
        rst        : in STD_LOGIC;
        
        -- Input: Q2.12 format
        data_in    : in WORD_ARRAY_16(0 to NUM_CHANNELS-1);
        valid_in   : in STD_LOGIC;
        
        -- Output: Q1.6 format
        data_out   : out WORD_ARRAY(0 to NUM_CHANNELS-1);
        valid_out  : out STD_LOGIC
    );
end q_scaler;

architecture Behavioral of q_scaler is
    -- Keep simple integer constants for clamps and rounding. This avoids multiple resize/compare steps
    constant MAX_INT  : integer := 127;   -- maximum Q1.6 value (signed 8-bit)
    constant MIN_INT  : integer := -128;  -- minimum Q1.6 value
    constant ROUND_INT: integer := 2 ** (SHIFT_AMOUNT - 1); -- rounding addend (32 for shift 6)

    -- Pipeline register for valid
    signal valid_reg : std_logic := '0';

begin

    -- Scale pipeline: clocked to keep timing stable with other pipeline stages
    scale_process: process(clk)
        -- small temporaries as integers to make arithmetic and saturation explicit
        variable input_s     : signed(INPUT_WIDTH-1 downto 0);
        variable in_signed   : signed(INPUT_WIDTH-1 downto 0);
        variable shifted_s   : signed(INPUT_WIDTH-1 downto 0);
        variable shifted_int : integer;
        variable clamped_int : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_reg <= '0';
                for i in 0 to NUM_CHANNELS-1 loop
                    data_out(i) <= (others => '0');
                end loop;
            else
                valid_reg <= valid_in;

                if valid_in = '1' then
                    for i in 0 to NUM_CHANNELS-1 loop
                        -- read input
                        input_s := signed(data_in(i));

                        if SKIP_SHIFT then
                            -- Bypass scaling: treat input as already in target Q-format
                            -- Direct conversion to integer (no rounding or shift)
                            shifted_int := to_integer(input_s);
                        else
                            -- symmetric round-to-nearest: add ROUND for non-negative, subtract ROUND for negative
                            if input_s >= 0 then
                                in_signed := input_s + to_signed(ROUND_INT, INPUT_WIDTH);
                            else
                                in_signed := input_s - to_signed(ROUND_INT, INPUT_WIDTH);
                            end if;

                            -- arithmetic right shift by SHIFT_AMOUNT
                            shifted_s := shift_right(in_signed, SHIFT_AMOUNT);

                            -- convert to integer for easy clamping
                            shifted_int := to_integer(shifted_s);
                        end if;

                        -- clamp to 8-bit signed range
                        if shifted_int > MAX_INT then
                            clamped_int := MAX_INT;
                        elsif shifted_int < MIN_INT then
                            clamped_int := MIN_INT;
                        else
                            clamped_int := shifted_int;
                        end if;

                        -- assign output as sized signed converted to std_logic_vector
                        data_out(i) <= std_logic_vector(to_signed(clamped_int, OUTPUT_WIDTH));
                    end loop;
                end if;
            end if;
        end if;
    end process;

    valid_out <= valid_reg;

end Behavioral;
