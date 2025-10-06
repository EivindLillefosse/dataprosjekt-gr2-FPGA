architecture Behavioral of MAC is
   signal macc_result : std_logic_vector(width_p-1 downto 0);
   signal macc_result_prev : std_logic_vector(width_p-1 downto 0);
   signal valid_d : std_logic := '0';
   signal valid_d2 : std_logic := '0';
   signal output_changed : std_logic := '0';
   signal timeout_done : std_logic := '0';
   signal valid_extended : std_logic := '0';
   signal done_internal : std_logic := '0';

begin
   process(clk)
   begin
      if rising_edge(clk) then
         if rst = '1' or clear = '1' then
            valid_d <= '0';
            valid_d2 <= '0';
            valid_extended <= '0';
            macc_result_prev <= (others => '0');
         else
            valid_d <= valid_extended;
            valid_d2 <= valid_d;
            macc_result_prev <= macc_result;
            
            -- Keep valid high until done
            if valid = '1' then
               valid_extended <= '1';
            elsif done_internal = '1' then
               valid_extended <= '0';
            end if;
         end if;
      end if;
   end process;

   -- Combinatorial output change detection (reacts immediately)
   output_changed <= '1' when (macc_result /= macc_result_prev and (valid_d = '1' or valid_d2 = '1')) else '0';
   
   -- Timeout after 2 cycles (1 extra cycle)
   timeout_done <= valid_d2;
   
   -- Done when either output changes or timeout
   done_internal <= output_changed or timeout_done;
   done <= done_internal;

   MACC_MACRO_inst : MACC_MACRO
   generic map (
      DEVICE => "7SERIES",
      LATENCY => 1,
      WIDTH_A => width_a,
      WIDTH_B => width_b,
      WIDTH_P => width_p)
   port map (
      P         => macc_result,
      A         => pixel_in,
      ADDSUB    => '1',           -- Always add
      B         => weights,
      CARRYIN   => '0',           -- No carry
      CE        => valid_extended and not done_internal, -- CE low when done is high
      CLK       => clk,
      LOAD      => '0',           -- Never load
      LOAD_DATA => (others => '0'),
      RST       => clear or rst   -- Reset on clear or rst
   );

   result <= macc_result;

end Behavioral;