-- Self-checking testbench for axis_reg_slice.
-- Run: scripts/run_sims.sh axis_reg_slice

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; -- uniform(), for random gaps and backpressure

entity axis_reg_slice_tb is
end entity axis_reg_slice_tb;

architecture sim of axis_reg_slice_tb is
	constant CLK_PERIOD : time     := 10 ns;
	constant DATA_WIDTH : positive := 32;
	constant NUM_BEATS  : positive := 1000; -- beats the source sends

	signal aclk    : std_logic := '0';
	signal aresetn : std_logic := '0';

	-- Upstream side (TB is the source, drives the DUT's s_axis)
	signal s_axis_tdata  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
	signal s_axis_tvalid : std_logic                                 := '0';
	signal s_axis_tready : std_logic;
	signal s_axis_tlast  : std_logic := '0';

	-- Downstream side (TB is the sink, receives the DUT's m_axis)
	signal m_axis_tdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);
	signal m_axis_tvalid : std_logic;
	signal m_axis_tready : std_logic := '0';
	signal m_axis_tlast  : std_logic;

	signal done : boolean := false; -- set by the checker when all beats arrived
begin
	aclk <= not aclk after CLK_PERIOD / 2;

	dut : entity work.axis_reg_slice
		generic map(
			DATA_WIDTH => DATA_WIDTH
		)
		port map
		(
			aclk          => aclk,
			aresetn       => aresetn,
			s_axis_tdata  => s_axis_tdata,
			s_axis_tvalid => s_axis_tvalid,
			s_axis_tready => s_axis_tready,
			s_axis_tlast  => s_axis_tlast,
			m_axis_tdata  => m_axis_tdata,
			m_axis_tvalid => m_axis_tvalid,
			m_axis_tready => m_axis_tready,
			m_axis_tlast  => m_axis_tlast
		);

	-- Reset: hold aresetn low for a few cycles, release it on a clock edge.
	reset_proc : process
	begin
		aresetn <= '0';
		for i in 1 to 5 loop
			wait until rising_edge(aclk);
		end loop;
		aresetn <= '1';
		wait;
	end process;

	-- Source: send beats 0, 1, 2, ... NUM_BEATS-1 on s_axis.
	source_proc : process
		variable i     : natural  := 0;
		variable seed1 : positive := 1;
		variable seed2 : positive := 2;
		variable r     : real;
	begin
		wait until aresetn = '1';
		wait until rising_edge(aclk);

		while i < NUM_BEATS loop
			s_axis_tlast  <= '0';
			s_axis_tdata  <= std_logic_vector(to_unsigned(i, DATA_WIDTH));
			s_axis_tvalid <= '1';

			if i = NUM_BEATS - 1 then
				s_axis_tlast <= '1';
			end if;

			wait until rising_edge(aclk);

			if s_axis_tready = '1' and s_axis_tvalid = '1' then
				i := i + 1;

				-- Random gap: idle cycles (tvalid = '0') before the next beat, 30% each.
				-- Only allowed here, right after a transfer: once tvalid is high it must
				-- stay high until the beat transfers.
				uniform(seed1, seed2, r);
				while r < 0.3 loop
					s_axis_tvalid <= '0';
					wait until rising_edge(aclk);
					uniform(seed1, seed2, r);
				end loop;
			end if;
		end loop;

		s_axis_tvalid <= '0';
		s_axis_tlast  <= '0';
		wait;
	end process;

	-- Sink: random backpressure. Each cycle tready is '1' with probability 70%.
	-- (A sink may change tready at any time; only the source has rules.)
	sink_proc : process
		variable seed1 : positive := 7;
		variable seed2 : positive := 11;
		variable r     : real;
	begin
		wait until aresetn = '1';

		loop
			uniform(seed1, seed2, r);
			if r < 0.7 then
				m_axis_tready <= '1';
			else
				m_axis_tready <= '0';
			end if;
			wait until rising_edge(aclk);
		end loop;
	end process;

	-- Checker: on each rising edge with m_axis_tvalid = '1' and m_axis_tready = '1',
	-- compare m_axis_tdata/tlast with the expected beat. Sample here, in a clocked
	-- process, not in the source process (delta-cycle pitfall).
	checker_proc : process (aclk)
		variable i             : natural := 0;
		variable expected_last : std_logic;
	begin
		if rising_edge(aclk) then
			if m_axis_tvalid = '1' and m_axis_tready = '1' then
				if i = NUM_BEATS - 1 then
					expected_last := '1';
				else
					expected_last := '0';
				end if;

				assert to_integer(unsigned(m_axis_tdata)) = i
				report "beat " & integer'image(i) & ": got tdata 0x" & to_hstring(m_axis_tdata)
					severity error;
				assert m_axis_tlast = expected_last
				report "beat " & integer'image(i) & ": got tlast " & std_logic'image(m_axis_tlast)
					severity error;

				i := i + 1;
				if i = NUM_BEATS then
					done <= true;
				end if;
			end if;
		end if;
	end process;

	-- Ends the simulation: pass when done, fail if it never gets there.
	control_proc : process
	begin
		wait until done for 100 us; -- watchdog
		assert done report "Timeout: not all beats arrived" severity failure;
		report "PASS: all beats received";
		std.env.finish;
	end process;
end architecture sim;
