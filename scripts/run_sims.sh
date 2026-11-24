#!/usr/bin/env bash
# Runs every self-checking testbench (ip/<core>/sim/vhdl/*_tb.vhd) with GHDL.
# Usage: scripts/run_sims.sh [core ...]   (no args = all cores)
# A test fails if GHDL exits non-zero, i.e. an assert of severity error/failure fired.
set -uo pipefail
shopt -s nullglob # a core may have a model and testbench before it has RTL

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHDL_FLAGS=(--std=08)

if [ $# -gt 0 ]; then cores=("$@"); else
  cores=()
  for d in "$ROOT"/ip/*/; do cores+=("$(basename "$d")"); done
fi

passed=(); failed=()
for core in "${cores[@]}"; do
  tbs=("$ROOT/ip/$core"/sim/vhdl/*_tb.vhd)
  [ ${#tbs[@]} -gt 0 ] || continue
  work="$ROOT/build/sim/$core"
  mkdir -p "$work"

  ghdl -i "${GHDL_FLAGS[@]}" --workdir="$work" \
    "$ROOT/ip/$core"/rtl/vhdl/*.vhd "$ROOT/ip/$core"/sim/vhdl/*.vhd

  for tb_file in "${tbs[@]}"; do
    tb="$(basename "$tb_file" .vhd)"
    echo "=== $core/$tb"
    if (cd "$work" && ghdl -m "${GHDL_FLAGS[@]}" --workdir=. "$tb" &&
        ghdl -r "${GHDL_FLAGS[@]}" --workdir=. "$tb" \
          --assert-level=error --wave="$tb.ghw"); then
      passed+=("$core/$tb")
    else
      failed+=("$core/$tb")
    fi
  done
done

echo
for t in ${passed[@]+"${passed[@]}"}; do echo "PASS  $t"; done
for t in ${failed[@]+"${failed[@]}"}; do echo "FAIL  $t"; done

total=$(( ${#passed[@]} + ${#failed[@]} ))
if [ "$total" -eq 0 ]; then echo "No testbenches found."; exit 1; fi
[ ${#failed[@]} -eq 0 ]
