-- Testbench for pmod_ad1. SKELETON: it connects everything but checks nothing yet,
-- except that the two AD7476A models report an error for every broken timing limit.
-- Run: scripts/run_sims.sh pmod_ad1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; -- uniform(), for random stimulus

entity pmod_ad1_tb is
end entity pmod_ad1_tb;

architecture sim of pmod_ad1_tb is
	constant ACLK_FREQ     : positive := 100_000_000;
	constant SCLK_FREQ     : positive := 20_000_000;
	constant SAMPLE_PERIOD : positive := 102;
	constant FRAME_LEN     : natural  := 0;

	constant CLK_PERIOD : time := 1 sec / ACLK_FREQ;
	constant VDD        : real := 3.3;
	constant LSB        : real := VDD / 4096.0;

	signal aclk    : std_logic := '0';
	signal aresetn : std_logic := '0';

	-- Analog inputs, in volts. (code + 0.5) * LSB converts to exactly that code.
	signal vin0 : real := 1000.5 * LSB;
	signal vin1 : real := 3000.5 * LSB;

	-- Pmod pins
	signal spi_csn   : std_logic;
	signal spi_sclk  : std_logic;
	signal spi_data0 : std_logic;
	signal spi_data1 : std_logic;

	-- Downstream side (TB is the sink, receives the DUT's m_axis)
	signal m_axis_tdata  : std_logic_vector(31 downto 0);
	signal m_axis_tvalid : std_logic;
	signal m_axis_tready : std_logic := '0';
	signal m_axis_tlast  : std_logic;

	signal overflow : std_logic;
begin
	aclk <= not aclk after CLK_PERIOD / 2;

	dut : entity work.pmod_ad1
		generic map(
			ACLK_FREQ     => ACLK_FREQ,
			SCLK_FREQ     => SCLK_FREQ,
			SAMPLE_PERIOD => SAMPLE_PERIOD,
			FRAME_LEN     => FRAME_LEN
		)
		port map
		(
			aclk          => aclk,
			aresetn       => aresetn,
			spi_csn       => spi_csn,
			spi_sclk      => spi_sclk,
			spi_data0     => spi_data0,
			spi_data1     => spi_data1,
			m_axis_tdata  => m_axis_tdata,
			m_axis_tvalid => m_axis_tvalid,
			m_axis_tready => m_axis_tready,
			m_axis_tlast  => m_axis_tlast,
			overflow      => overflow
		);

	adc0 : entity work.ad7476a_model
		generic map(
			VDD => VDD
		)
		port map
		(
			vin        => vin0,
			cs_n       => spi_csn,
			sclk       => spi_sclk,
			sdata      => spi_data0,
			violations => open
		);

	adc1 : entity work.ad7476a_model
		generic map(
			VDD => VDD
		)
		port map
		(
			vin        => vin1,
			cs_n       => spi_csn,
			sclk       => spi_sclk,
			sdata      => spi_data1,
			violations => open
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

	-- Stimulus on vin0/vin1: YOUR CODE (step 3)

	-- Sink, m_axis_tready: YOUR CODE (step 4)

	-- Checker on m_axis_*: YOUR CODE (step 4)

	-- Ends the simulation after 20 sample periods. Replace it when the checker
	-- knows how many beats to expect: pass when done, fail on a timeout.
	control_proc : process
	begin
		wait for 20 * SAMPLE_PERIOD * CLK_PERIOD;
		report "SKELETON: simulation ended, no samples were checked";
		std.env.finish;
	end process;
end architecture sim;
