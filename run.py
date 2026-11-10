import os
import sys
from pathlib import Path

from vunit import VUnit

ROOT = Path(__file__).resolve().parent
UVVM_PATH = Path(os.environ.get("UVVM_PATH", ROOT.parent / "UVVM"))
UVVM_LIBS = ["uvvm_util", "uvvm_vvc_framework", "bitvis_vip_axistream"]
GHDL_UVVM_FLAGS = ["-frelaxed", "-Wno-hide", "-Wno-shared"]

if not (UVVM_PATH / "uvvm_util").is_dir():
    sys.exit(f"UVVM not found at {UVVM_PATH}; set UVVM_PATH to your UVVM checkout")

vu = VUnit.from_argv()

for name in UVVM_LIBS:
    script_dir = UVVM_PATH / name / "script"
    lib = vu.add_library(name)
    # compile_order.txt: a "# library <name>" header, then paths relative to script/
    for line in (script_dir / "compile_order.txt").read_text().splitlines()[1:]:
        if line.strip():
            lib.add_source_file(script_dir / line.strip())
    lib.add_compile_option("ghdl.a_flags", GHDL_UVVM_FLAGS)

lib = vu.add_library("signal_chain")
lib.add_source_files(ROOT / "ip" / "*" / "rtl" / "vhdl" / "*.vhd")
lib.add_source_files(ROOT / "ip" / "*" / "sim" / "uvvm" / "*.vhd")
lib.add_compile_option("ghdl.a_flags", GHDL_UVVM_FLAGS)

vu.set_sim_option("ghdl.elab_flags", ["-frelaxed"])

vu.main()
