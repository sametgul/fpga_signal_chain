-- AXI4-Stream register slice: registers TDATA/TVALID/TLAST forward and
-- TREADY backward, at full throughput (1 beat/cycle), using a one-entry skid buffer.
-- See docs/axis_reg_slice.md for a walkthrough and timing diagram.
library ieee;
use ieee.std_logic_1164.all;

entity axis_reg_slice is
	generic (
		DATA_WIDTH : positive := 32
	);
	port (
		aclk    : in std_logic;
		aresetn : in std_logic;

		s_axis_tdata  : in std_logic_vector(DATA_WIDTH - 1 downto 0);
		s_axis_tvalid : in std_logic;
		s_axis_tready : out std_logic;
		s_axis_tlast  : in std_logic;

		m_axis_tdata  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
		m_axis_tvalid : out std_logic;
		m_axis_tready : in std_logic;
		m_axis_tlast  : out std_logic
	);
end entity axis_reg_slice;

architecture rtl of axis_reg_slice is
	-- Main register: drives m_axis_* directly; the beat downstream sees.
	signal m_valid : std_logic := '0';
	signal m_data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
	signal m_last  : std_logic;

	-- Skid buffer: holds the one extra beat accepted after downstream stalls,
	-- because s_axis_tready only drops one cycle later.
	signal skid_valid : std_logic := '0';
	signal skid_data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
	signal skid_last  : std_logic;
begin

	-- Comes straight from a flop, never from m_axis_tready: this cuts the
	-- backward combinational path. Ready whenever the skid is empty.
	s_axis_tready <= not skid_valid;

	m_axis_tvalid <= m_valid;
	m_axis_tdata  <= m_data;
	m_axis_tlast  <= m_last;

	process (aclk)
	begin
		if rising_edge(aclk) then
			-- Main register is empty or its beat is being taken: it can load.
			if m_valid = '0' or m_axis_tready = '1' then
				if skid_valid = '1' then
					-- Drain the skid first to keep beat order. s_axis_tready is 0
					-- this cycle, so no new input beat arrives.
					m_valid    <= '1';
					m_data     <= skid_data;
					m_last     <= skid_last;
					skid_valid <= '0';
				else
					-- Normal pass-through: input goes straight to the output.
					m_valid <= s_axis_tvalid;
					m_data  <= s_axis_tdata;
					m_last  <= s_axis_tlast;
				end if;
			elsif s_axis_tvalid = '1' and skid_valid = '0' then
				-- Output stalled, but s_axis_tready was still 1, so this input beat
				-- was accepted. Park it in the skid; s_axis_tready drops next cycle.
				skid_valid <= '1';
				skid_data  <= s_axis_tdata;
				skid_last  <= s_axis_tlast;
			end if;

			-- Only the valid flags are reset; data registers stay reset-free.
			-- Data is ignored while valid is low, and this keeps the reset
			-- net's fanout small. Placed last so it overrides the logic above.
			if aresetn = '0' then
				m_valid    <= '0';
				skid_valid <= '0';
			end if;
		end if;
	end process;

end architecture rtl;
