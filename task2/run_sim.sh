#!/usr/bin/env bash
# Simulate the task 2 accelerator with Verilator (works on macOS/Linux, no Vivado needed).
#
#   ./run_sim.sh                              # simulates pic1.pgm
#   ./run_sim.sh ../other_images/cross.pgm    # simulates another image
#
# Setup (macOS):  brew install verilator
# Output:  build/<name>_result.pgm  and  build/<name>_result.png
# The provided testbench/memory/clock files are not modified; the testbench is
# copied into build/ with the image path patched in.
set -euo pipefail
cd "$(dirname "$0")"

IMG="${1:-pic1.pgm}"
command -v verilator >/dev/null || { echo "verilator not found (brew install verilator)"; exit 1; }
[ -f "$IMG" ] || { echo "image not found: $IMG"; exit 1; }

NAME="$(basename "$IMG" .pgm)"

# GNU Make cannot build in paths containing spaces, so build in a temp dir.
WORK="$(mktemp -d /tmp/acc_sim.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cp memory2.sv clock.sv acc2.sv "$WORK/"
cp "$IMG" "$WORK/$NAME.pgm"          # memory2 writes the result next to the source file
sed -E "s#(load_file_name = )\"[^\"]*\"#\1\"$WORK/$NAME.pgm\"#" test2.sv > "$WORK/test2.sv"

(cd "$WORK" && verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD --top-module testbench \
  memory2.sv clock.sv acc2.sv test2.sv >/dev/null && ./obj_dir/Vtestbench)

rm -rf build && mkdir build
cp "$WORK/$NAME.pgm" "$WORK/${NAME}_result.pgm" build/
python3 -I check_result.py "build/$NAME.pgm" "build/${NAME}_result.pgm"
