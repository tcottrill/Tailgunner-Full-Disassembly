"""Regenerate and verify every Tailgunner listing from a ROM set.

usage: python gen_from_roms.py [ROMS] [--traces]

ROMS is a MAME 'tailg' zip or a directory holding the four chips (found by
CRC32, any file names); the default is ../roms. Steps:

  1. romset.py      build/tailg_8k.bin, the 8K program image
  2. trace/run_traces.py  (when build/trace_*.json are missing, or --traces)
  3. analyze.py     code / data separation -> build/analysis.json
  4. emit.py        tailgunner_program_rom.asm
  5. emit_defines.py tailgunner_defines.asm
  6. verify.py      must print MISMATCHES : 0 and PAGE ERRORS : 0
  7. emit_shapes.py shapes_preview.html

Any failing step prints !! and the exit status is 1.
"""
import glob, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import romset


def run(*args):
    r = subprocess.run([sys.executable] + list(args), cwd=HERE)
    if r.returncode:
        print("!! %s failed" % args[0])
        sys.exit(1)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    img = romset.build_image(args[0] if args else None)
    print("ROM image: %s (%d bytes)" % (romset.IMAGE, len(img)))
    if "--traces" in sys.argv or not glob.glob(os.path.join(romset.BUILD, "trace_*.json")):
        run(os.path.join("trace", "run_traces.py"))
    run("analyze.py")
    run("emit.py")
    run("emit_defines.py")
    run("verify.py")
    run("emit_shapes.py")


if __name__ == "__main__":
    main()
