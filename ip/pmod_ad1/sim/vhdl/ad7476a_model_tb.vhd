-- Testbench for the AD7476A model itself: does it behave like the datasheet?
-- Run: scripts/run_sims.sh pmod_ad1
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ad7476a_model_tb is
end entity ad7476a_model_tb;

architecture sim of ad7476a_model_tb is
	constant VDD    : real := 3.3;
	constant LSB    : real := VDD / 4096.0;
	constant PERIOD : time := 1020 ns; -- the core's default sample period

	signal vin        : real      := 0.0;
	signal cs_n       : std_logic := '1';
	signal sclk       : std_logic := '1';
	signal sdata      : std_logic;
	signal violations : natural;
begin
	dut : entity work.ad7476a_model
		generic map(
			VDD                => VDD,
			VIOLATION_SEVERITY => note -- this testbench breaks the limits on purpose
		)
		port map
		(
			vin        => vin,
			cs_n       => cs_n,
			sclk       => sclk,
			sdata      => sdata,
			violations => violations
		);

	main_proc : process
		variable word     : std_logic_vector(15 downto 0);
		variable expected : natural := 0; -- violations so far

		-- One conversion. Reads SDATA on each falling edge, into word. CS rises after
		-- num_edges falling edges, and the procedure returns one cycle after CS fell.
		procedure convert(
			num_edges : natural := 16;
			t2        : time    := 20 ns;
			t_low     : time    := 30 ns;
			t_high    : time    := 30 ns;
			cycle     : time    := PERIOD) is
			variable start : time;
		begin
			start := now;
			word  := (others => '-');
			cs_n  <= '0';
			wait for t2;
			for k in 1 to num_edges loop
				word(16 - k) := sdata;
				sclk <= '0';
				wait for t_low;
				sclk <= '1';
				wait for t_high;
			end loop;
			cs_n <= '1';
			if start + cycle > now then
				wait for start + cycle - now;
			end if;
		end procedure;

		procedure expect_code(code : natural; msg : string) is
		begin
			-- The first zero is read on falling edge 1, before t3 has passed, so it is skipped.
			assert word(14 downto 12) = "000" and word(11 downto 0) = std_logic_vector(to_unsigned(code, 12))
			report msg & ": got " & to_string(word) severity error;
		end procedure;

		procedure expect_invalid(msg : string) is
		begin
			assert word(11 downto 0) = (11 downto 0 => 'X')
			report msg & ": got " & to_string(word) severity error;
		end procedure;

		procedure expect_sdata(value : std_logic; msg : string) is
		begin
			assert sdata = value report msg & ": got " & std_logic'image(sdata) severity error;
		end procedure;

		procedure expect_violations(added : natural; msg : string) is
		begin
			expected := expected + added;
			assert violations = expected
			report msg & ": " & integer'image(violations) & " violations, expected " & integer'image(expected) severity error;
			expected := violations;
		end procedure;

		procedure recover is -- back to a known good state
		begin
			wait for 2 us;
			convert;
			convert;
			expected := violations;
		end procedure;
	begin
		-- Power-up in power-down mode: the first conversion is a dummy
		vin <= 1234.5 * LSB;
		wait for 1 us;
		expect_sdata('Z', "before the first conversion");
		convert;
		expect_invalid("dummy conversion");
		convert;
		expect_code(1234, "first valid conversion");

		-- Transfer function: code transitions at 1 LSB, 2 LSB, ...
		vin <= 0.0;                convert; expect_code(0, "0 V");
		vin <= 0.99 * LSB;         convert; expect_code(0, "just below 1 LSB");
		vin <= 1.01 * LSB;         convert; expect_code(1, "just above 1 LSB");
		vin <= 2048.5 * LSB;       convert; expect_code(2048, "mid-scale");
		vin <= 4094.99 * LSB;      convert; expect_code(4094, "just below the last transition");
		vin <= 4095.01 * LSB;      convert; expect_code(4095, "just above the last transition");
		vin <= VDD + 0.2;          convert; expect_code(4095, "above VDD");
		vin <= - 0.2;              convert; expect_code(0, "below 0 V");
		vin <= 2650.5 * LSB;       convert; expect_code(16#A5A#, "bit order");

		-- The sample is taken when CS falls, not later
		vin <= 1000.5 * LSB;
		vin <= transport 3000.5 * LSB after 5 ns;
		wait for 1 ns;
		convert;
		expect_code(1000, "sampling instant");

		-- SDATA over one frame, code 0x800: only DB11 is '1'
		vin  <= 2048.5 * LSB;
		wait for 1 ns;
		cs_n <= '0';
		wait for 21 ns;
		expect_sdata('X', "before t3");
		wait for 2 ns;
		expect_sdata('0', "after t3");
		wait for 7 ns;
		for k in 1 to 16 loop
			sclk <= '0'; -- falling edge k
			wait for 9 ns;
			if k = 5 then
				expect_sdata('1', "DB11 held for t7");
			end if;
			wait for 1 ns;
			expect_sdata('X', "after t7, edge " & integer'image(k));
			wait for 20 ns;
			sclk <= '1';
			if k < 16 then
				wait for 9 ns;
				expect_sdata('X', "before t4, edge " & integer'image(k));
				wait for 2 ns;
				if k = 4 then
					expect_sdata('1', "DB11 after t4");
				else
					expect_sdata('0', "bit after t4, edge " & integer'image(k));
				end if;
				wait for 19 ns;
			else
				wait for 5 ns;
				expect_sdata('X', "before t8");
				wait for 2 ns;
				expect_sdata('Z', "after t8");
			end if;
		end loop;
		cs_n <= '1';
		wait for 500 ns;

		-- Nothing so far broke a limit
		expect_violations(0, "legal traffic");

		-- Power modes: depends on the falling edges before CS rises
		vin <= 777.5 * LSB;
		wait for 1 us;
		convert(num_edges => 1);
		convert;
		expect_code(777, "CS high after edge 1: stays in normal mode");
		convert(num_edges => 2);
		convert;
		expect_invalid("CS high after edge 2: power-down");
		convert;
		expect_code(777, "awake after one dummy");
		convert(num_edges => 9);
		convert(num_edges => 9);
		convert;
		expect_invalid("CS high after edge 9, twice: still in power-down");
		convert;
		expect_code(777, "awake after a full dummy");
		convert(num_edges => 10);
		expect_sdata('Z', "terminated conversion");
		convert;
		expect_code(777, "CS high after edge 10: stays in normal mode");
		expect_violations(0, "power modes");

		-- Waking up takes 1 us: at 900 ns the chip isn't ready (and this is above 1 MSPS)
		convert(num_edges => 5);
		convert(t_low => 25 ns, t_high => 25 ns, cycle => 900 ns);
		convert;
		expect_invalid("less than 1 us after waking up");
		recover;

		-- The fastest legal settings
		convert(t2 => 10 ns, t_low => 25 ns, t_high => 25 ns, cycle => 1000 ns);
		convert(t2 => 10 ns, t_low => 20 ns, t_high => 30 ns, cycle => 1000 ns);
		convert(t2 => 10 ns, t_low => 30 ns, t_high => 20 ns, cycle => 1000 ns);
		convert;
		expect_violations(0, "fastest legal settings");

		-- Each limit, broken on its own
		convert(t2 => 9 ns);
		expect_violations(1, "t2");
		convert(t_low => 24 ns, t_high => 25 ns);
		expect_violations(15, "SCLK too fast"); -- 15 periods
		convert(t_low => 23 ns, t_high => 37 ns);
		expect_violations(15, "t5");
		convert(t_low => 37 ns, t_high => 23 ns);
		expect_violations(15, "t6");
		recover;
		convert(t_low => 25 ns, t_high => 25 ns, cycle => 990 ns);
		convert;
		expect_violations(1, "more than 1 MSPS");
		convert(t_low => 30 ns, t_high => 30 ns, cycle => 1010 ns); -- tACQ: 1020 ns needed
		convert;
		expect_violations(1, "tACQ");
		recover;

		-- tQUIET alone: 16 falling edges at 100 ns, then CS high 10 ns and low again
		cs_n <= '0';
		wait for 20 ns;
		for k in 1 to 16 loop
			sclk <= '0';
			wait for 50 ns;
			if k < 16 then
				sclk <= '1';
				wait for 50 ns;
			end if;
		end loop;
		sclk <= '1'; -- 50 ns after falling edge 16, 14 ns after t8
		cs_n <= '1';
		wait for 20 ns; -- tQUIET = 34 ns
		convert;
		expect_violations(1, "tQUIET");
		recover;

		-- t1 alone: CS idles low after the conversion, then pulses high for 9 ns
		cs_n <= '0';
		wait for 20 ns;
		for k in 1 to 16 loop
			sclk <= '0';
			wait for 30 ns;
			sclk <= '1';
			wait for 30 ns;
		end loop;
		wait for 200 ns;
		cs_n <= '1';
		wait for 9 ns;
		convert;
		expect_violations(1, "t1");

		report "PASS: the model behaves like the datasheet";
		std.env.finish;
	end process;
end architecture sim;
