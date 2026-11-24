# fpga_signal_chain

Reusable, CI-tested FPGA signal-chain blocks: ADC → DSP → DAC. All blocks connect over AXI4-Stream, and AXI4-Lite or full AXI4 is used wherever the Zynq PS connects.

The target board is a ZedBoard with a Pmod AD1 (ADC) and a Pmod DA4 (DAC). The cores themselves are board-agnostic: board-specific details live only in `projects/`.

Every core has a specification and a self-checking testbench that is itself tested by breaking the design on purpose. See the [design and verification flow](docs/development_flow.md).

For learning and reference material, see [logic_playground](https://github.com/sametgul/logic_playground).

## Layout

```
ip/<core>/
  README.md        what the core does, its ports and design notes
  docs/            longer notes and images for this core (e.g. testbench walkthrough)
  rtl/vhdl/        synthesizable source (VHDL-2008, no vendor primitives)
  sim/vhdl/        self-checking testbenches, named *_tb.vhd
projects/<name>/   board projects, rebuilt from Tcl (from stage 2)
docs/              repo-wide notes: stream contract, AXI-Stream terms, development flow
scripts/           run_sims.sh: runs every testbench with GHDL
```

Later stages add `rtl/sv`, `hls` and `matlab` folders. Every implementation of a core shares the same ports and the same [stream contract](docs/stream_contract.md).

## Running the tests

You only need GHDL.

```sh
scripts/run_sims.sh                    # run every testbench
scripts/run_sims.sh axis_reg_slice     # run one core's testbenches
```

Each testbench writes its waveform to `build/sim/<core>/<testbench>.ghw`. Open it with a viewer that reads GHW, such as [Surfer](https://surfer-project.org/) (standalone or as a VS Code extension) or GTKWave.

Testbenches are plain, self-checking VHDL-2008. A failed `assert` with severity `error` or `failure` fails the test, and a testbench ends with `std.env.finish`. CI runs the same script on every push.

## Vivado

Vivado is not part of the simulation flow. Board projects are rebuilt from Tcl with `vivado -mode batch -source create_project.tcl`. Generated project files such as `.xpr` and `.runs/` are never committed.

## Roadmap

Each stage adds exactly one new unknown.

| # | Deliverable | New unknown |
|---|---|---|
| 0 | Repo, GHDL regression, CI, `axis_reg_slice` with a self-checking testbench | Build and test infrastructure |
| 1 | Pmod AD1 core with a self-checking testbench | The AD1 protocol and its model |
| 2 | ZedBoard bring-up, PL only, ILA | Constraints and hardware debug |
| 3 | Pmod DA4 sink, then ADC → DAC passthrough | Two converters' timing across one stream |
| 4 | First FIR, coefficients over AXI4-Lite | Fixed point and a register interface |
| 5 | More filters (biquad, CIC, ...) | None; this stage is reuse |
| — | PS-only track: DDR test, Ethernet echo | Runs separately, before stage 6 |
| 6 | Zynq PS7, bare-metal register access | PS–PL integration and Vitis |
| 7 | AXI DMA to DDR through an HP port | DMA and memory-mapped AXI |
| 8 | Streaming to a PC over Ethernet (lwIP) | Networking |
| 9 | Own AXI4 full master and slave | Writing AXI4 yourself |
| 10 | UVVM versions of earlier testbenches, SV ports, cocotb with numpy reference models, HLS, MATLAB HDL Coder | Verification frameworks, additional languages and flows |

Stage 3, the ADC → DAC passthrough working on hardware, is the gate before stage 10.
