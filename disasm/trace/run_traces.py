"""Build tgtrace.exe if needed and run every script in trace/scripts/ on the
ROM image, writing build/trace_<script>.json (and frame SVGs in build/svg).

usage: python trace/run_traces.py [--rebuild]
"""
import glob, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
DISASM = os.path.dirname(HERE)
sys.path.insert(0, DISASM)
import romset

EXE = os.path.join(HERE, "tgtrace.exe")


def build():
    r = subprocess.run(["cmd", "/c", os.path.join(HERE, "build_trace.bat")], capture_output=True, text=True)
    if r.returncode or not os.path.exists(EXE):
        print(r.stdout, r.stderr)
        raise SystemExit("!! could not build tgtrace.exe (Visual Studio 2022 is needed)")


def main():
    if "--rebuild" in sys.argv or not os.path.exists(EXE):
        build()
    romset.load_image()
    svg = os.path.join(romset.BUILD, "svg")
    os.makedirs(svg, exist_ok=True)
    for script in sorted(glob.glob(os.path.join(HERE, "scripts", "*.txt"))):
        name = os.path.splitext(os.path.basename(script))[0]
        out = os.path.join(romset.BUILD, "trace_%s.json" % name)
        r = subprocess.run([EXE, romset.IMAGE, script, out, svg], capture_output=True, text=True)
        if r.returncode:
            raise SystemExit("!! %s: %s" % (name, r.stderr))
        print("%-14s %s" % (name, r.stdout.strip().splitlines()[-1]))


if __name__ == "__main__":
    main()
