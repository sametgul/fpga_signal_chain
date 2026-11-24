-- Pmod AD1 (2x AD7476A) to AXI4-Stream, at a fixed sample rate.
-- See ip/pmod_ad1/README.md for the specification.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; -- ceil(), for constants only

entity pmod_ad1 is
	generic (
		ACLK_FREQ     : positive := 100_000_000; -- Hz
		SCLK_MAX      : positive := 20_000_000;  -- Hz, upper limit for SCLK
		SAMPLE_PERIOD : positive := 102;         -- aclk cycles, CS falling to CS falling
		FRAME_LEN     : natural  := 0            -- beats per tlast, 0 = never
	);
	port (
		aclk    : in std_logic;
		aresetn : in std_logic;

		spi_csn   : out std_logic;
		spi_sclk  : out std_logic;
		spi_data0 : in std_logic;
		spi_data1 : in std_logic;

		m_axis_tdata  : out std_logic_vector(31 downto 0);
		m_axis_tvalid : out std_logic;
		m_axis_tready : in std_logic;
		m_axis_tlast  : out std_logic;

		overflow : out std_logic
	);
end entity pmod_ad1;

architecture rtl of pmod_ad1 is
	-- TODO: constants from the generics
begin
	-- TODO: asserts on the generics

	-- TODO: CS and SCLK
	spi_csn  <= '1';
	spi_sclk <= '1';

	-- TODO: shift registers, discard the first conversion

	-- TODO: 16-bit conversion, tvalid
	m_axis_tdata  <= (others => '0');
	m_axis_tvalid <= '0';

	-- TODO: overflow, tlast
	m_axis_tlast <= '0';
	overflow     <= '0';

end architecture rtl;
