-- Behavioral model of one AD7476A ADC, written from the datasheet (Rev. G).
-- Simulation only. Section, table and figure names below refer to the datasheet.
--
-- SDATA shows the worst case the datasheet allows: while a bit may be changing it
-- is 'X', and while nobody drives it, it is 'Z'. A core that samples at the wrong
-- moment therefore gets 'X' or 'Z'. A conversion made while the chip isn't fully
-- powered up returns 'X'.
--
-- A broken timing limit is reported with VIOLATION_SEVERITY and counted on
-- the violations port.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; -- floor()

entity ad7476a_model is
	generic (
		VDD                : real           := 3.3;  -- supply = reference, in volts
		START_POWERED_DOWN : boolean        := true; -- the chip can power up in either mode
		VIOLATION_SEVERITY : severity_level := error
	);
	port (
		vin        : in real; -- analog input, in volts
		cs_n       : in std_logic;
		sclk       : in std_logic;
		sdata      : out std_logic;
		violations : out natural
	);
end entity ad7476a_model;

architecture sim of ad7476a_model is
	-- Table 4
	constant T_SCLK_MIN : time := 50 ns; -- 20 MHz
	constant T_QUIET    : time := 50 ns;
	constant T1         : time := 10 ns;
	constant T2         : time := 10 ns;
	constant T3         : time := 22 ns;
	constant T4         : time := 40 ns;
	constant T7         : time := 9.5 ns; -- the 3.3 V < VDD <= 3.6 V row: the safe value around 3.3 V
	constant T8         : time := 36 ns;
	constant T_POWER_UP : time := 1 us;
	constant PULSE_MIN  : real := 0.4; -- t5, t6 as a fraction of tSCLK
	-- Table 1
	constant T_ACQ          : time := 250 ns;
	constant T_CYCLE_MIN    : time := 1 us; -- 1 MSPS
	constant LONG_AGO       : time := - 1 ms;
	constant NUM_SCLK_EDGES : natural := 16;

	-- Code transitions are at 1 LSB, 2 LSB, ... with LSB = VDD/4096 (ADC Transfer Function).
	function to_code(v : real) return std_logic_vector is
		variable scaled : real := v / VDD * 4096.0;
	begin
		if scaled < 0.0 then
			scaled := 0.0;
		elsif scaled > 4095.0 then
			scaled := 4095.0;
		end if;
		return std_logic_vector(to_unsigned(integer(floor(scaled)), 12));
	end function;
begin

	process (cs_n, sclk)
		variable frame      : std_logic_vector(15 downto 0); -- 4 leading zeros + code
		variable converting : boolean := false;              -- CS low, fewer than 16 falling edges so far
		variable edges      : natural := 0;                  -- SCLK falling edges since CS fell
		variable powered    : boolean := not START_POWERED_DOWN;
		variable in_track   : boolean := true; -- track-and-hold (already in track at power-on)

		variable t_cs_fall     : time := LONG_AGO;
		variable t_cs_rise     : time := LONG_AGO;
		variable t_sclk_fall   : time := LONG_AGO;
		variable t_sclk_rise   : time := LONG_AGO;
		variable t_track       : time := LONG_AGO; -- when the track-and-hold went to track
		variable t_three_state : time := LONG_AGO; -- when SDATA is in three-state at the latest
		variable t_ready       : time := LONG_AGO; -- when the chip is fully powered up
		variable count         : natural := 0;

		procedure check(ok : boolean; msg : string) is
		begin
			if not ok then
				count := count + 1;
				report "AD7476A: " & msg severity VIOLATION_SEVERITY;
			end if;
		end procedure;

		procedure go_to_track is
		begin
			if not in_track then
				in_track := true;
				t_track  := now;
			end if;
		end procedure;
	begin
		-- Start of a conversion (Serial Interface)
		if falling_edge(cs_n) then
			check(now - t_cs_rise >= T1, "t1: CS high for " & to_string(now - t_cs_rise, 1 ns));
			check(now - t_three_state >= T_QUIET, "tQUIET: " & to_string(now - t_three_state, 1 ns));
			check(now - t_cs_fall >= T_CYCLE_MIN, "more than 1 MSPS: CS period " & to_string(now - t_cs_fall, 1 ns));
			check(not powered or (in_track and now - t_track >= T_ACQ), "tACQ: not enough time in track");

			t_cs_fall := now;
			in_track  := false; -- hold: vin is sampled here
			edges      := 0;
			converting := true;
			if powered and now >= t_ready then
				frame := "0000" & to_code(vin);
			else
				frame := (others => 'X');
			end if;
			sdata <= transport 'X', frame(15) after T3;
		end if;

		-- The chip wakes up on CS falling: the track-and-hold returns to track on the
		-- first SCLK edge (Power-Up Time, Point A in Figure 22).
		if sclk'event and converting and edges = 0 and not powered then
			go_to_track;
		end if;

		if falling_edge(sclk) then
			if converting then
				if edges = 0 then
					check(now - t_cs_fall >= T2, "t2: first SCLK falling edge " & to_string(now - t_cs_fall, 1 ns) & " after CS");
				else
					check(now - t_sclk_fall >= T_SCLK_MIN, "SCLK faster than 20 MHz: period " & to_string(now - t_sclk_fall, 1 ns));
					check(t_sclk_rise - t_sclk_fall >= PULSE_MIN * (now - t_sclk_fall), "t5: SCLK low too short");
					check(now - t_sclk_rise >= PULSE_MIN * (now - t_sclk_fall), "t6: SCLK high too short");
				end if;

				edges := edges + 1;
				if edges < NUM_SCLK_EDGES then
					sdata <= transport 'X' after T7, frame(15 - edges) after T4;
				else
					sdata <= transport 'X' after T7, 'Z' after T8;
					t_three_state := now + T8;
					converting    := false;
				end if;
			end if;
			t_sclk_fall := now;
		end if;

		if rising_edge(sclk) then
			-- Point B: back to track on the rising edge after the 13th falling edge
			if edges = 13 and converting then
				go_to_track;
			end if;
			t_sclk_rise := now;
		end if;

		if rising_edge(cs_n) then
			-- The power mode depends on when CS rises (Modes of Operation)
			if edges >= 10 then
				if not powered then
					powered := true;
					t_ready := t_cs_fall + T_POWER_UP;
				end if;
			elsif edges >= 2 then
				powered := false;
			end if;

			-- Too early: the conversion is terminated. The datasheet gives no time from CS
			-- rising to three-state; the model assumes t8.
			if converting then
				converting := false;
				sdata <= transport 'X', 'Z' after T8;
				t_three_state := now + T8;
				go_to_track;
			end if;
			t_cs_rise := now;
		end if;

		-- Before the first conversion nobody drives SDATA.
		if t_cs_fall = LONG_AGO then
			sdata <= 'Z';
		end if;
		violations <= count;
	end process;

end architecture sim;
