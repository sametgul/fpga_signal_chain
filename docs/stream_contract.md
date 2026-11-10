# Stream contract

Every block between the ADC and the DAC follows this contract, so any filter fits between any source and any sink.

## Interface

- AXI4-Stream ports, named so Vivado's IP packager detects them automatically: `aclk`, `aresetn`, `s_axis_*`, `m_axis_*`.
- The signals used are `TDATA`, `TVALID`, `TREADY` and `TLAST`. `TKEEP`, `TSTRB`, `TUSER`, `TID` and `TDEST` are left out unless a core's own documentation says otherwise.
- `aresetn` is active low, synchronous, and held for several cycles. Check the reset rules of any Xilinx IP on the same bus.
- Standard AXI handshake: a beat transfers on a rising `aclk` edge when `TVALID` and `TREADY` are both high. Once `TVALID` is high, it and `TDATA` must not change until that transfer happens.

## Sample format

- Every channel is a **16-bit two's-complement** value in Q1.15 format, covering -1.0 to just under +1.0.
- **One beat carries one sample instant.** Multi-channel streams put channel 0 in `TDATA[15:0]`, channel 1 in `TDATA[31:16]`, and so on.
- Converter-specific formats appear only inside small adapter cores, never in filters:

| Converter | Native format | Adapter |
|---|---|---|
| Pmod AD1 (AD7476A) | 12-bit unsigned, offset binary | `s = (code - 2048) << 4` |
| Pmod DA4 (AD5628) | 12-bit unsigned | `code = (s >> 4) + 2048` |

## `TLAST`

- `TLAST` marks the end of a frame, for consumers that work in blocks such as DMA or Ethernet.
- A source asserts it every `FRAME_LEN` beats; set `FRAME_LEN = 0` to never assert it.
- A processing core passes `TLAST` through with the sample it belongs to.

## Real-time rules

Converters run on a fixed sample clock and cannot wait for the stream.

- **ADC source:** never stalls. If `TREADY` is low when a new sample is ready, the sample is **dropped** and a sticky `overflow` flag is set.
- **DAC sink:** if no new sample has arrived by its update time, it **holds the last value** and sets a sticky `underflow` flag.
- **Processing cores:** must sustain one beat per sample period on average. They may stall briefly, but their worst-case latency must fit inside the source's slack.

Both flags stay set until reset, or until the AXI-Lite register is written once that wrapper exists. A flag that is set during a test or on hardware is a bug, not something to tune around.

## Analog notes

Both Pmods are **unipolar**, so signed zero corresponds to mid-scale on the analog side:

- **AD1 input:** 0 V to VCC (3.3 V on the ZedBoard). Signed 0 corresponds to about 1.65 V. Bipolar test signals need a DC offset at the input.
- **DA4 output:** 0 V to about 2.5 V using its internal reference. Signed 0 corresponds to about 1.25 V. The internal reference has to be switched on by a command at power-up. **Verify this in the AD5628 datasheet before writing the DA4 core.**
