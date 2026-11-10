-- AXI4-Stream register slice: registers TDATA/TVALID/TLAST forward and
-- TREADY backward, at full throughput (1 beat/cycle), using a one-entry skid buffer.
library ieee;
use ieee.std_logic_1164.all;

entity axis_reg_slice is
  generic (
    DATA_WIDTH : positive := 32
  );
  port (
    aclk          : in  std_logic;
    aresetn       : in  std_logic;

    s_axis_tdata  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    s_axis_tvalid : in  std_logic;
    s_axis_tready : out std_logic;
    s_axis_tlast  : in  std_logic;

    m_axis_tdata  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in  std_logic;
    m_axis_tlast  : out std_logic
  );
end entity axis_reg_slice;

architecture rtl of axis_reg_slice is
  signal m_valid    : std_logic := '0';
  signal m_data     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal m_last     : std_logic;

  signal skid_valid : std_logic := '0';
  signal skid_data  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal skid_last  : std_logic;
begin

  s_axis_tready <= not skid_valid;

  m_axis_tvalid <= m_valid;
  m_axis_tdata  <= m_data;
  m_axis_tlast  <= m_last;

  process (aclk)
  begin
    if rising_edge(aclk) then
      if m_valid = '0' or m_axis_tready = '1' then
        if skid_valid = '1' then
          m_valid    <= '1';
          m_data     <= skid_data;
          m_last     <= skid_last;
          skid_valid <= '0';
        else
          m_valid <= s_axis_tvalid;
          m_data  <= s_axis_tdata;
          m_last  <= s_axis_tlast;
        end if;
      elsif s_axis_tvalid = '1' and skid_valid = '0' then
        skid_valid <= '1';
        skid_data  <= s_axis_tdata;
        skid_last  <= s_axis_tlast;
      end if;

      -- Only the valid flags are reset; data registers stay reset-free.
      if aresetn = '0' then
        m_valid    <= '0';
        skid_valid <= '0';
      end if;
    end if;
  end process;

end architecture rtl;
