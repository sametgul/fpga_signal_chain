# fpga_signal_chain

Reusable, CI-tested FPGA signal-chain blocks: ADC → DSP → DAC. All blocks connect over AXI4-Stream, and AXI4-Lite or full AXI4 is used wherever the Zynq PS connects.

The target board is a ZedBoard with a Pmod AD1 (ADC) and a Pmod DA4 (DAC). The cores themselves are board-agnostic: board-specific details live only in `projects/`.

For learning and reference material, see [logic_playground](https://github.com/sametgul/logic_playground).

## Layout

```
ip/<core>/
  rtl/vhdl/        synthesizable source (VHDL-2008, no vendor primitives)
  sim/uvvm/        self-checking UVVM testbenches, run by VUnit
projects/<name>/   board projects, rebuilt from Tcl (from stage 2)
docs/              stream contract and design notes
run.py             VUnit test runner
```

Later stages add `rtl/sv`, `hls` and `matlab` folders under each core. Every implementation of a core shares the same ports and the same [stream contract](docs/stream_contract.md).

## Running the tests

You need GHDL, Python 3 (CI uses 3.13), and a checkout of [UVVM](https://github.com/UVVM/UVVM). CI pins UVVM to commit `90d56e9`.

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
export UVVM_PATH=/path/to/UVVM           # defaults to ../UVVM
.venv/bin/python run.py -p 4             # run all tests
.venv/bin/python run.py "*throughput*"   # run matching tests
.venv/bin/python run.py --gui <test>     # open the waveform viewer
```

The first run compiles the UVVM libraries this repo needs. Later runs recompile only what changed.

## Vivado

Vivado is not part of the simulation flow. Board projects are rebuilt from Tcl with `vivado -mode batch -source create_project.tcl`. Generated project files such as `.xpr` and `.runs/` are never committed.

## Roadmap

Each stage adds exactly one new unknown.

| # | Deliverable | New unknown |
|---|---|---|
| 0 | Repo, VUnit + UVVM regression, CI, `axis_reg_slice` | Build and test infrastructure |
| 1 | Pmod AD1 core with a UVVM testbench | The AD1 protocol and its model |
| 2 | ZedBoard bring-up, PL only, ILA | Constraints and hardware debug |
| 3 | Pmod DA4 sink, then ADC → DAC passthrough | Two converters' timing across one stream |
| 4 | First FIR, coefficients over AXI4-Lite | Fixed point and a register interface |
| 5 | More filters (biquad, CIC, ...) | None; this stage is reuse |
| — | PS-only track: DDR test, Ethernet echo | Runs separately, before stage 6 |
| 6 | Zynq PS7, bare-metal register access | PS–PL integration and Vitis |
| 7 | AXI DMA to DDR through an HP port | DMA and memory-mapped AXI |
| 8 | Streaming to a PC over Ethernet (lwIP) | Networking |
| 9 | Own AXI4 full master and slave | Writing AXI4 yourself |
| 10 | SV ports, cocotb with numpy reference models, HLS, MATLAB HDL Coder | Additional languages and flows |

Stage 3, the ADC → DAC passthrough working on hardware, is the gate before stage 10.
