# How the AD7476A converts: SAR and track-and-hold

The AD7476A on the Pmod AD1 is a 12-bit **successive-approximation (SAR)** ADC. This page explains how such an ADC works and what that means for the core that drives it. Back to the core: [README.md](../README.md).

The datasheet covers three chips: the AD7476A (12-bit), AD7477A (10-bit) and AD7478A (8-bit). The Pmod AD1 uses the **AD7476A**, so only its rows in the tables apply.

## SAR: a binary search

A SAR ADC finds the input voltage by binary search, one bit per step. It has three parts:

- **Track-and-hold:** a switch and a capacitor that freeze the input voltage.
- **Internal DAC:** produces a test voltage from the bits decided so far.
- **Comparator:** answers one question per step: "is the input above or below the test voltage?"

Example: a 4-bit SAR with a 3.2 V reference, so each step is 0.2 V. The input is 2.05 V.

| Step | Try code | Test voltage | Input ≥ test? | Bit |
|---|---|---|---|---|
| 1 (MSB) | `1000` | 1.6 V | yes | **1** |
| 2 | `1100` | 2.4 V | no | **0** |
| 3 | `1010` | 2.0 V | yes | **1** |
| 4 (LSB) | `1011` | 2.2 V | no | **0** |

The result is `1010` = 10, and 10 × 0.2 V = 2.0 V: the nearest step at or below 2.05 V.

Each step tries setting the next bit to 1. If the input is still at or above the test voltage, the bit stays 1; otherwise it goes back to 0. A 12-bit SAR needs 12 such steps.

## Track-and-hold

The comparator needs an input that holds still for all 12 steps. The track-and-hold provides that, in two phases:

- **Track:** the switch is closed, and the capacitor follows the input voltage.
- **Hold:** the switch opens, and the capacitor keeps the voltage it had at that instant. The binary search runs against this frozen value.

**The moment the switch opens is the moment the sample is taken.**

The datasheet says the track-and-hold "can handle input frequencies in excess of 13 MHz": it can follow signals far faster than the 500 kHz Nyquist limit of a 1 MSPS converter. Two consequences:

- **Aliasing.** Anything up to about 13 MHz at the input gets sampled and folds back into the band below Nyquist as a false frequency. The Pmod's anti-aliasing filter (2 poles, 500 kHz cutoff) reduces this but doesn't remove it: just above a 500 kHz Nyquist limit it attenuates only a few dB, and at lower sample rates signals between Nyquist and 500 kHz pass straight through.
- **Acquisition time.** After a conversion, the capacitor has to track the input again before the next hold. This is a physical reason for a minimum quiet time between conversions (look for the track-and-hold acquisition time in the specs).

## What this means for the core

- **The FPGA clocks the conversion.** The AD7476A has no internal conversion clock: each SCLK cycle drives one step of the search. So the number of SCLK cycles per conversion is fixed by the chip, and SCLK speed sets the sample rate.
- **The bits come out in the order they are decided.** The most significant bit is decided first, and each bit is known as soon as its step is done. The serial timing diagram shows exactly what comes out on SDATA, and in which order.
- **CS sets the sample instant.** The hold starts when CS falls, so any jitter in when the core pulls CS low becomes jitter in the sampling instant, which costs SNR on hardware. Generate CS from a steady clock enable at exactly regular intervals.
- **No pipeline delay.** The 12 bits read in one conversion belong to the sample taken at the start of that same conversion, not to an earlier one. (Fast pipelined ADCs return a result that is several conversions old.)
