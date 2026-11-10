library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
use vunit_lib.run_pkg.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axistream;
context bitvis_vip_axistream.vvc_context;

entity axis_reg_slice_tb is
  generic (
    runner_cfg : string
  );
end entity axis_reg_slice_tb;

architecture tb of axis_reg_slice_tb is
  constant C_CLK_PERIOD : time    := 10 ns;
  constant C_DATA_WIDTH : natural := 32;
  constant C_SRC        : natural := 0; -- VVC driving the DUT input
  constant C_SINK       : natural := 1; -- VVC receiving the DUT output

  signal clk       : std_logic := '0';
  signal clock_ena : boolean   := false;
  signal aresetn   : std_logic := '0';

  signal axis_in  : t_axistream_if(tdata(C_DATA_WIDTH - 1 downto 0),
                                   tkeep(C_DATA_WIDTH / 8 - 1 downto 0),
                                   tuser(0 downto 0),
                                   tstrb(C_DATA_WIDTH / 8 - 1 downto 0),
                                   tid(0 downto 0),
                                   tdest(0 downto 0));
  signal axis_out : t_axistream_if(tdata(C_DATA_WIDTH - 1 downto 0),
                                   tkeep(C_DATA_WIDTH / 8 - 1 downto 0),
                                   tuser(0 downto 0),
                                   tstrb(C_DATA_WIDTH / 8 - 1 downto 0),
                                   tid(0 downto 0),
                                   tdest(0 downto 0));

  signal beats      : natural := 0;
  signal first_beat : time    := 0 ns;
  signal last_beat  : time    := 0 ns;
begin

  i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

  p_clock : clock_generator(clk, clock_ena, C_CLK_PERIOD, "aclk");

  i_dut : entity work.axis_reg_slice
    generic map (
      DATA_WIDTH => C_DATA_WIDTH
    )
    port map (
      aclk          => clk,
      aresetn       => aresetn,
      s_axis_tdata  => axis_in.tdata,
      s_axis_tvalid => axis_in.tvalid,
      s_axis_tready => axis_in.tready,
      s_axis_tlast  => axis_in.tlast,
      m_axis_tdata  => axis_out.tdata,
      m_axis_tvalid => axis_out.tvalid,
      m_axis_tready => axis_out.tready,
      m_axis_tlast  => axis_out.tlast
    );

  -- Sideband signals the DUT does not have
  axis_out.tkeep <= (others => '1');
  axis_out.tuser <= (others => '0');
  axis_out.tstrb <= (others => '0');
  axis_out.tid   <= (others => '0');
  axis_out.tdest <= (others => '0');

  i_src : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      GC_VVC_IS_MASTER => true,
      GC_DATA_WIDTH    => C_DATA_WIDTH,
      GC_INSTANCE_IDX  => C_SRC
    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_in
    );

  i_sink : entity bitvis_vip_axistream.axistream_vvc
    generic map (
      GC_VVC_IS_MASTER => false,
      GC_DATA_WIDTH    => C_DATA_WIDTH,
      GC_INSTANCE_IDX  => C_SINK
    )
    port map (
      clk              => clk,
      axistream_vvc_if => axis_out
    );

  p_output_monitor : process (clk)
  begin
    if rising_edge(clk) then
      if axis_out.tvalid = '1' and axis_out.tready = '1' then
        if beats = 0 then
          first_beat <= now;
        end if;
        last_beat <= now;
        beats     <= beats + 1;
      end if;
    end if;
  end process;

  test_runner_watchdog(runner, 1 ms);

  p_main : process
    variable v_data : t_slv_array(0 to 63)(C_DATA_WIDTH - 1 downto 0);
    variable v_len  : positive;
  begin
    test_runner_setup(runner, runner_cfg);
    await_uvvm_initialization(VOID);

    for idx in C_SRC to C_SINK loop
      shared_axistream_vvc_config(idx).bfm_config.clock_period        := C_CLK_PERIOD;
      shared_axistream_vvc_config(idx).bfm_config.check_packet_length := true;
    end loop;

    clock_ena <= true;
    wait for 5 * C_CLK_PERIOD;
    wait until rising_edge(clk);
    aresetn   <= '1';

    while test_suite loop

      if run("single_packet") then
        for i in 0 to 15 loop
          v_data(i) := std_logic_vector(to_unsigned(i, C_DATA_WIDTH));
        end loop;
        axistream_transmit(AXISTREAM_VVCT, C_SRC, v_data(0 to 15), "ramp");
        axistream_expect(AXISTREAM_VVCT, C_SINK, v_data(0 to 15), "ramp");
        await_completion(AXISTREAM_VVCT, C_SINK, 10 us);

      elsif run("random_gaps_and_backpressure") then
        shared_axistream_vvc_config(C_SRC).bfm_config.valid_low_at_word_num          := C_MULTIPLE_RANDOM;
        shared_axistream_vvc_config(C_SRC).bfm_config.valid_low_multiple_random_prob := 0.3;
        shared_axistream_vvc_config(C_SRC).bfm_config.valid_low_duration             := C_RANDOM;
        shared_axistream_vvc_config(C_SRC).bfm_config.valid_low_max_random_duration  := 4;

        shared_axistream_vvc_config(C_SINK).bfm_config.ready_low_at_word_num          := C_MULTIPLE_RANDOM;
        shared_axistream_vvc_config(C_SINK).bfm_config.ready_low_multiple_random_prob := 0.5;
        shared_axistream_vvc_config(C_SINK).bfm_config.ready_low_duration             := C_RANDOM;
        shared_axistream_vvc_config(C_SINK).bfm_config.ready_low_max_random_duration  := 5;

        for pkt in 1 to 20 loop
          v_len := random(1, v_data'length);
          for i in 0 to v_len - 1 loop
            v_data(i) := random(C_DATA_WIDTH);
          end loop;
          axistream_transmit(AXISTREAM_VVCT, C_SRC, v_data(0 to v_len - 1), "random packet");
          axistream_expect(AXISTREAM_VVCT, C_SINK, v_data(0 to v_len - 1), "random packet");
          await_completion(AXISTREAM_VVCT, C_SINK, 100 us);
        end loop;

      elsif run("full_throughput") then
        shared_axistream_vvc_config(C_SINK).bfm_config.ready_default_value := '1';
        for i in v_data'range loop
          v_data(i) := random(C_DATA_WIDTH);
        end loop;
        axistream_transmit(AXISTREAM_VVCT, C_SRC, v_data, "back-to-back");
        axistream_expect(AXISTREAM_VVCT, C_SINK, v_data, "back-to-back");
        await_completion(AXISTREAM_VVCT, C_SINK, 10 us);
        wait until rising_edge(clk);

        check_value(beats, v_data'length, ERROR, "output beat count");
        check_value(last_beat - first_beat, (v_data'length - 1) * C_CLK_PERIOD, ERROR,
                    "output beats must be on consecutive cycles");
      end if;

    end loop;

    report_alert_counters(FINAL);
    test_runner_cleanup(runner);
  end process p_main;

end architecture tb;
