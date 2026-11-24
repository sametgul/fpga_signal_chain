# Pmod AD1 core `pmod_ad1`

Reads both ADCs of a Pmod AD1 at a fixed sample rate and outputs the samples as an AXI4-Stream that follows the [stream contract](../../docs/stream_contract.md).

This page is the specification for the RTL. Figure and table numbers refer to the AD7476A datasheet (Rev. G).

## Sources

- AD7476A datasheet (Analog Devices): <https://www.analog.com/media/en/technical-documentation/data-sheets/AD7476A_7477A_7478A.pdf>
- Pmod AD1 reference manual (Digilent): <https://digilent.com/reference/pmod/pmodad1/reference-manual>

Background:

- [How a SAR ADC and its track-and-hold work](docs/sar_adc.md)
- [Measuring the ADC: FFT, SNR, SINAD and ENOB](docs/fft_measurement.md) (the stage-2 targets)

## The board

Two AD7476A chips share CS and SCLK, and each has its own data line. Both therefore sample at the same instant, and one conversion gives one sample per channel.

| J1 pin | Signal | Direction (FPGA) | Use |
|---|---|---|---|
| 1 | CS | out | Shared, active low |
| 2 | D0 | in | SDATA of ADC 1 (analog input A0), channel 0 |
| 3 | D1 | in | SDATA of ADC 2 (analog input A1), channel 1 |
| 4 | SCK | out | Shared SCLK |
| 5 | GND | | |
| 6 | VCC | | 3.3 V on the ZedBoard. Also the ADC reference, so full scale is 0 V to VCC |

Each input has a 2-pole Sallen-Key anti-alias filter with a 500 kHz cutoff.

## The protocol

### 1. CS falling and the SDATA frame

CS falling takes the sample (the track-and-hold goes to hold), starts the conversion, and takes SDATA out of three-state within t3 (Figure 3).

One frame is 16 SCLK cycles: 4 leading zeros, then DB11 (MSB) down to DB0. Each bit is read on the falling edge after the one that clocked it out.

| Bit | Clocked out by | Read on |
|---|---|---|
| Leading zeros 1 to 4 | CS falling, then SCLK falling edges 1 to 3 | not used |
| DB11 | SCLK falling edge 4 | SCLK falling edge **5** |
| DB0 | SCLK falling edge 15 | SCLK falling edge **16** |

SDATA returns to three-state within t8 of falling edge 16 (Serial Interface). Outside the frame it floats, so it must not be read.

What happens if CS rises before the frame is complete (Modes of Operation):

| CS rises | Result |
|---|---|
| Before the 2nd SCLK falling edge | Conversion terminated, stays in normal mode |
| After the 2nd and before the 10th | Conversion terminated, **power-down** |
| After the 10th and before the 16th | Conversion terminated, stays in normal mode |

The rules for the core:

- **CS stays low for all 16 SCLK cycles.**
- **Discard the first conversion after every reset.** The chip can start in either mode, and a reset in the middle of a frame can put it into power-down by raising CS early. One dummy cycle is always enough to wake it, at any SCLK frequency up to 20 MHz (Power-Up Time).
- **After reset, wait one full sample period before the first CS falling edge.** A reset may have cut a frame short, and tQUIET, tACQ and the 1 MSPS limit still apply.

### 2. SCLK edges

- SCLK idles **high**. The first edge after CS falls is a falling edge, at least t2 later.
- SDATA changes after the **falling** edge: the old bit holds for at least t7, and the new one is valid within t4.
- The core samples on the **next falling edge**.

At the default SCLK (tSCLK = 60 ns), measured at the chip from the falling edge that clocks a bit out:

| Time | SDATA |
|---|---|
| 0 to 9.5 ns | previous bit |
| 9.5 to 40 ns | unknown |
| 40 to 69.5 ns | this bit. The next falling edge is at 60 ns |

The rising edge, at 30 ns, falls in the unknown region. The Serial Interface section allows rising-edge reading only for a slower SCLK.

Inside the FPGA, the round-trip delay *d* (SCLK out to the chip, SDATA back) shifts this window later. The setup margin is tSCLK − 40 − *d*, and the hold margin is 9.5 + *d*. The value of *d* comes from stage 2.

### 3. Speed limits

| Limit | Value | Source |
|---|---|---|
| SCLK frequency | 20 MHz max | Table 4 |
| SCLK high and low time (t5, t6) | 0.4 × tSCLK min each | Table 4 |
| CS falling to first SCLK falling edge (t2) | 10 ns min | Table 4 |
| SDATA three-state to next CS falling (tQUIET) | 50 ns min | Table 4 |
| CS high time (t1) | 10 ns min | Table 4 |
| Track-and-hold acquisition (tACQ) | 250 ns min to allow | Table 1 |
| Throughput | 1 MSPS max | Table 1 |

### 4. Cycles per conversion and sample rate

The time from one CS falling edge to the next must satisfy both:

- **Acquisition** (Figure 4): t2 + 12.5 × tSCLK + tACQ. The track-and-hold returns to track at point B, while the last bits are still shifting out.
- **Serial interface:** t2 + 15 × tSCLK + t8 + tQUIET.

**Default: `aclk` = 100 MHz, SCLK = `aclk` / 6 = 16.7 MHz, one sample every 102 cycles = 980.4 kSPS.**

With 10 ns steps, t2 = 20 ns (one step above the minimum), t8 = 36 ns, tQUIET = 50 ns and tACQ = 250 ns:

| Condition | Calculation | Needed | Available |
|---|---|---|---|
| Acquisition | 20 + 12.5 × 60 + 250 | 1020 ns | 1020 ns |
| Serial interface | 20 + 15 × 60 + 36 + 50 | 1006 ns | 1020 ns |

The acquisition condition has no slack beyond the datasheet's worst-case tACQ. Each extra cycle in the sample period adds 10 ns.

#### Why not 1 MSPS

At 16.7 MHz the acquisition condition takes 20 ns more than the 1 µs period. Even with the minimum t2 of 10 ns, 1 MSPS needs an SCLK of at least 16.9 MHz, and from 100 MHz the next integer divider up is 5 (20 MHz). The options compared (*d* is the round-trip delay from section 2):

| `aclk` | SCLK | Duty cycle | Max sample rate | Margin on t5, t6 | Sample point | Setup margin | Hold margin |
|---|---|---|---|---|---|---|---|
| **100 MHz / 6** | **16.7 MHz** | **50/50** | **980 kSPS** | **6 ns** | **60 ns** | **20 − *d*** | **9.5 + *d*** |
| 100 MHz / 5 | 20 MHz | 40/60 | 1 MSPS | 0 ns | 50 ns | 10 − *d* | 9.5 + *d* |
| 40 MHz / 2 | 20 MHz | 50/50 | 1 MSPS | 5 ns | 50 ns | 10 − *d* | 9.5 + *d* |
| 120 MHz / 6 | 20 MHz | 50/50 | 1 MSPS | 5 ns | 58.3 ns | 18.3 − *d* | 1.2 + *d* |
| 105 MHz / 6 | 17.5 MHz | 50/50 | 1 MSPS | 5.7 ns | 57.1 ns | 17.1 − *d* | 9.5 + *d* |

- **100 MHz / 5** leaves no margin on the SCLK pulse width.
- **40 MHz / 2** fixes the pulse width but not the setup margin, needs an MMCM on the ZedBoard (100 MHz oscillator), and leaves later filters 40 clock cycles per sample.
- **120 MHz / 6** gains setup margin by sampling one `aclk` step after the falling edge, but gives up most of the hold margin. It also needs an MMCM.
- **105 MHz / 6** is the best of these for exactly 1 MSPS (105 cycles): it samples on the falling edge with good margin on both sides. It also needs an MMCM.

Giving up 2 % of the sample rate doubles the setup margin of the 100 MHz / 5 option and needs no extra clock.

### 5. Output format

The core outputs the contract's 16-bit signed format directly. `pmod_ad1` is already the converter-specific core, so it acts as the adapter the contract describes, and no raw format leaves it. The conversion is wiring only:

```
s = (code - 2048) << 4 = not code(11) & code(10 downto 0) & "0000"
```

Code transitions occur at whole LSBs (1 LSB, 2 LSB, ...), with 1 LSB = VDD / 4096 (ADC Transfer Function). So code = floor(4096 × Vin / VDD), limited to 4095.

| Input | Code | Output |
|---|---|---|
| 0 V | 0 | −32768 |
| VCC / 2 | 2048 | 0 |
| Full scale | 4095 | 32752 |

To get back from the output sample `s` (one 16-bit channel):

| Wanted | Formula |
|---|---|
| Raw code, in VHDL | `not s(15) & s(14 downto 4)` |
| Raw code, as a number | s / 16 + 2048 |
| Voltage at the ADC input | VCC × (s + 32768) / 65536 |

The core has no separate raw output, because the raw code is always recoverable this way.

One beat carries both channels: channel 0 in `TDATA[15:0]`, channel 1 in `TDATA[31:16]`.

## I/O timing (for stage 2 constraints)

At VDD = 3.3 V, from Table 4:

| Parameter | Datasheet name | Value |
|---|---|---|
| CS falling to SDATA driven | t3 | 22 ns max |
| SCLK falling to new bit valid | t4 | 40 ns max |
| SCLK falling to old bit still valid | t7 | 9.5 ns min (the 3.3 V to 3.6 V row; 10 ns at or below 3.3 V) |
| SCLK falling edge 16 to SDATA three-state | t8 | 36 ns max, t7 min |
| CS falling to first SCLK falling edge | t2 | 10 ns min |

## Entity

### Generics

| Generic | Type | Default | Meaning |
|---|---|---|---|
| `ACLK_FREQ` | positive | 100_000_000 | `aclk` frequency in Hz |
| `SCLK_MAX` | positive | 20_000_000 | Upper limit for SCLK in Hz, not the SCLK itself. The core uses the fastest SCLK it can make from `aclk` (50/50 duty cycle) within this limit: 16.7 MHz at 100 MHz, 20 MHz at 40 MHz |
| `SAMPLE_PERIOD` | positive | 102 | `aclk` cycles from one CS falling edge to the next. An `assert` rejects values below the minimum from section 4 |
| `FRAME_LEN` | natural | 0 | Beats per `TLAST`, 0 = never (stream contract) |

### Ports

| Port | Dir | Width | Reset value | Meaning |
|---|---|---|---|---|
| `aclk` | in | 1 | (input) | Main clock |
| `aresetn` | in | 1 | (input) | Synchronous reset, active low |
| `spi_csn` | out | 1 | 1 | Chip select, active low |
| `spi_sclk` | out | 1 | 1 | SPI clock, idles high |
| `spi_data0` | in | 1 | (input) | SDATA of ADC 1 (analog input A0), channel 0 |
| `spi_data1` | in | 1 | (input) | SDATA of ADC 2 (analog input A1), channel 1 |
| `m_axis_tdata` | out | 32 | not reset | Channel 1 in [31:16], channel 0 in [15:0] |
| `m_axis_tvalid` | out | 1 | 0 | A sample is available |
| `m_axis_tready` | in | 1 | (input) | The downstream block accepts the sample |
| `m_axis_tlast` | out | 1 | not reset | Last beat of a frame |
| `overflow` | out | 1 | 0 | Sticky: a sample was dropped. Cleared by reset |

The outputs with a reset value also start with that value when the FPGA is configured, before any reset. Data signals aren't reset, because they're ignored while `tvalid` is low.

### Stream behavior

The core holds one beat in its output register.

- **New sample, register empty:** the sample is loaded and `m_axis_tvalid` rises, whatever `m_axis_tready` is.
- **New sample, old beat accepted in the same cycle:** the old beat leaves and the new one is loaded. Nothing is dropped.
- **New sample, old beat still waiting:** the **new** sample is dropped and `overflow` is set. The old one stays, because AXI requires `tvalid` and the data to stay unchanged until the transfer.

Only loaded beats count towards `FRAME_LEN`. A dropped sample freezes the counter, so every frame has exactly `FRAME_LEN` beats, but it covers a longer time than `FRAME_LEN` sample periods. `overflow` marks that gap.

## Simulation model

[`ad7476a_model.vhd`](sim/vhdl/ad7476a_model.vhd) models one chip. It drives `'X'` on SDATA while a bit may be changing and `'Z'` while nobody drives the line, returns `'X'` data while powered down, and reports an error for every timing limit in section 3 that is broken. [`ad7476a_model_tb.vhd`](sim/vhdl/ad7476a_model_tb.vhd) checks the model against the datasheet.
