# Measuring the ADC: FFT, SNR, SINAD and ENOB

How the AD7476A datasheet measures dynamic performance, what the numbers mean, and what the stage-2 hardware measurement has to match. Back to the core: [README.md](../README.md). For how the converter itself works, see [sar_adc.md](sar_adc.md).

## The datasheet's test (Figure 7)

Feed a 100 kHz sine into the ADC, capture **8192 consecutive samples** at 1 MSPS, and take an FFT, which splits the signal into its frequencies. Figure 7 of the datasheet shows the result:

- **X axis, 0 to 500 kHz:** it ends at **Nyquist**, fs / 2. Sampling can't show anything above that.
- **Y axis:** power in dB relative to full scale (dBFS). 0 dB is a full-scale sine. The datasheet labels it "SNR (dB)".
- **Tall line at 100 kHz, near 0 dB:** the input sine.
- **Small spikes at 200, 300 and 400 kHz:** the 2nd, 3rd and 4th **harmonics**. That's distortion: the converter isn't perfectly linear, so a pure sine picks up copies at multiples of its frequency. Harmonics above Nyquist fold back into the plot (aliasing).
- **Grass along the bottom, about −95 to −115 dB:** noise.

Its legend reads: VDD = 2.7 V, SINAD = 72.05 dB, THD = −82.87 dB, SFDR = 87.24 dB.

## The numbers

| Name | What it compares | How to get it from the FFT |
|---|---|---|
| **SNR** | Signal against noise only | Signal power / sum of all noise bins (signal and harmonic bins excluded) |
| **THD** | All harmonics against the signal | Sum of the harmonic bins / signal power |
| **SFDR** | Signal against the single largest spur | Signal peak / largest other peak |
| **SINAD** | Signal against noise **plus** distortion | Signal power / everything else |
| **ENOB** | SINAD expressed as bits | (SINAD − 1.76) / 6.02 |

An ideal 12-bit converter has SNR = 6.02 × 12 + 1.76 ≈ **74 dB**. Figure 7's 72.05 dB SINAD corresponds to about **11.7 effective bits**.

## Targets for the Pmod AD1 (VDD = 3.3 V)

Use Table 1's rows for VDD = 2.35 V to 3.6 V. Figure 7 shows one typical chip at 2.7 V. The table's minimums are what's guaranteed.

| Spec | Guaranteed (25 °C) | Typical | ENOB |
|---|---|---|---|
| SINAD | 70 dB min | 71.5 dB | 11.3 (min), 11.6 (typ) |
| SNR | 71 dB min | — | |
| THD | — | −80 dB | |
| SFDR | — | 82 dB | |

A measured SINAD of about 68 to 71 dB means the core and board setup work as well as the chip allows. Something around 55 dB means something is wrong: a noisy or distorting signal source, grounding, jitter on CS, or a bug.

## Traps

**The noise floor is not the SNR.** The FFT spreads the total noise across N / 2 frequency bins, so each bin holds only a small share of it:

```
noise per bin ≈ −SNR − 10·log₁₀(N / 2)
              = −72 − 10·log₁₀(4096) ≈ −72 − 36 = −108 dBFS     (matches Figure 7)
```

To get the SNR, add up the power of all the noise bins. Reading the floor off the plot is off by about 36 dB.

**Spectral leakage.** An FFT assumes the capture repeats seamlessly. If the block doesn't hold a whole number of sine cycles, the ends don't match up, and the peak smears across many bins. Then the SNR comes out far too low. There are two fixes:

- **Coherent sampling:** choose the input frequency so that a whole number M of cycles fits in N samples: f_in = (M / N) × fs. Make M odd: with N a power of two, M and N then share no factors, so every sample lands at a different point on the sine. Example: N = 8192, fs = 1 MSPS, M = 819 → f_in = 99.976 kHz. The signal generator has to hit that frequency closely.
- **Window function**, for example Blackman-Harris: it tapers the ends of the block to zero, so they don't have to match. It's easier with a free-running generator. The signal then occupies a few bins, and they all count as signal.

**Full scale.** The input range is 0 V to VDD, so a full-scale sine is VDD peak-to-peak, centered at VDD / 2. Drive slightly below full scale (for example −0.5 dBFS) to avoid clipping, which shows up as strong harmonics. Then refer the results back to full scale.

**Bandwidth.** The input frequency must stay below the cutoff of the Pmod's anti-aliasing filter, or the filter, not the ADC, sets the result. Look up the cutoff in the Pmod AD1 reference manual.

## Clock jitter

Timing uncertainty in the sampling instant turns into noise. For a full-scale sine at frequency f and RMS jitter σ, jitter alone limits the SNR to:

```
SNR_jitter = −20·log₁₀(2π · f · σ)
```

| Jitter source | σ | Limit at f = 100 kHz |
|---|---|---|
| AD7476A aperture jitter | 30 ps | 94 dB, no problem |
| CS from a flop on a clean clock | a few ps to tens of ps | about 90 dB or better, no problem |
| CS with 1 ns of timing wander | 1 ns | 64 dB, ruins the measurement |

The sample is taken when CS falls, so CS must come straight from a flop clocked by a clean clock, at exactly regular intervals.

## What the core must provide (decided in stage 1)

- **No gaps.** A single dropped sample breaks the sine and smears the FFT. A capture made while the core's sticky `overflow` flag was set is invalid.
- **Even spacing.** CS falls at exactly regular intervals from a counter, so the sample rate is exact and known.
- **A plain `m_axis` stream.** 8192 samples is small, so in stage 2 an ILA can capture them straight off the stream. No DMA is needed for this measurement.

The analysis itself (FFT, window, SNR/SINAD/ENOB) is a short numpy script in stage 2.
