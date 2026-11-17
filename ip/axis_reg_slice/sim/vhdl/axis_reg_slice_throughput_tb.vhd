-- Throughput testbench for axis_reg_slice: with no input gaps and the sink
-- always ready, the slice must pass one beat per clock.
-- Run: scripts/run_sims.sh axis_reg_slice

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_reg_slice_throughput_tb is
end entity axis_reg_slice_throughput_tb;

architecture sim of axis_reg_slice_throughput_tb is
	constant CLK_PERIOD : time     := 10 ns;
	constant DATA_WIDTH : positive := 32;
	constant NUM_BEATS  : positive := 100; -- beats the source sends back to back

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

	signal done : boolean := false; -- set when the measurement is finished
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

	-- Sink: always ready, so the sink never slows the stream down.
	sink_proc : process
	begin
		wait until aresetn = '1';
		m_axis_tready <= '1';
		wait;
	end process;

	-- Source: send beats 0 .. NUM_BEATS-1 back to back, tlast on the last one.
	source_proc : process
		variable i : natural := 0;
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
			end if;
		end loop;

		s_axis_tvalid <= '0';
		s_axis_tlast  <= '0';
		wait;
	end process;

	-- Measurement: count clock cycles from the first input transfer to the last
	-- input transfer (tlast). A slow output side also shows up here: the slice
	-- holds at most 2 beats, so it must lower s_axis_tready within a few cycles.
	measure_proc : process (aclk)
		variable count           : natural := 0;
		variable first_beat_flag : boolean := false;
	begin
		if rising_edge(aclk) then
			if s_axis_tready = '1' and s_axis_tvalid = '1' then
				if count = 0 then
					first_beat_flag := true;
				else
					if s_axis_tlast = '1' then
						-- At one beat per clock, the first and last transfers are
						-- NUM_BEATS - 1 edges apart, so count is NUM_BEATS - 1 here.
						assert count < NUM_BEATS report "took " & integer'image(count) & " cycles" severity error;
						done <= true;
					end if;
				end if;
			end if;

			if first_beat_flag = true then
				count := count + 1;
			end if;

		end if;
	end process;

	-- Ends the simulation: pass when done, fail if it never gets there.
	control_proc : process
	begin
		wait until done for 100 us; -- watchdog
		assert done report "Timeout: measurement never finished" severity failure;
		report "PASS: throughput OK";
		std.env.finish;
	end process;
end architecture sim;
