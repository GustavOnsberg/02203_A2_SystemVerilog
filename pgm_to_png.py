#!/usr/bin/env python3
"""Convert a PGM image to PNG. Works on Windows and macOS (and Linux).

Run it and pick a .pgm file in the dialog; the PNG is saved next to it:

    python pgm_to_png.py              (Windows: py pgm_to_png.py)
    python3 pgm_to_png.py             (macOS)

You can also skip the dialog:  python3 pgm_to_png.py image.pgm [more.pgm ...]

Only the Python standard library is used (tkinter for the dialog, zlib for
the PNG encoder), so nothing needs to be installed. Supports ASCII (P2) and
binary (P5) PGM files, as written by the assignment's memory model / IrfanView.
"""
import struct
import sys
import zlib
from pathlib import Path


def read_pgm(path):
    """Return (width, height, maxval, pixels) where pixels is a list of ints."""
    data = Path(path).read_bytes()
    magic = data[:2]
    if magic not in (b"P2", b"P5"):
        raise ValueError(f"{Path(path).name}: not a PGM file (expected P2 or P5)")

    # Parse the header: 3 whitespace-separated numbers, '#' starts a comment.
    pos, header = 2, []
    while len(header) < 3:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while pos < len(data) and data[pos:pos + 1] not in (b"\n", b"\r"):
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        header.append(int(data[start:pos]))
    width, height, maxval = header
    pos += 1  # single whitespace byte after maxval

    count = width * height
    if magic == b"P2":
        values = [int(t) for t in data[pos:].split()[:count]]
    else:
        raw = data[pos:]
        if maxval < 256:
            values = list(raw[:count])
        else:  # 16-bit big-endian samples
            values = [(raw[2 * i] << 8) | raw[2 * i + 1] for i in range(count)]
    if len(values) != count:
        raise ValueError(f"{Path(path).name}: expected {count} pixels, found {len(values)}")
    return width, height, maxval, values


def write_png(path, width, height, maxval, values):
    """Write an 8-bit grayscale PNG (pixel values are rescaled if maxval != 255)."""
    if maxval != 255:
        values = [v * 255 // maxval for v in values]
    rows = b"".join(b"\x00" + bytes(values[y * width:(y + 1) * width]) for y in range(height))

    def chunk(tag, body):
        crc = zlib.crc32(tag + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", crc)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(rows, 9))
           + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


def convert(pgm_path):
    pgm_path = Path(pgm_path)
    out = pgm_path.with_suffix(".png")
    write_png(out, *read_pgm(pgm_path))
    return out


def pick_files():
    import tkinter as tk
    from tkinter import filedialog

    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)  # keep the dialog in front on Windows/macOS
    files = filedialog.askopenfilenames(
        title="Select PGM image(s) to convert to PNG",
        filetypes=[("PGM images", "*.pgm"), ("All files", "*.*")],
    )
    root.destroy()
    return list(files)


def main():
    files = sys.argv[1:]
    if not files:
        try:
            files = pick_files()
        except ImportError:
            sys.exit("tkinter is not available - pass the file on the command line instead:\n"
                     "  python3 pgm_to_png.py image.pgm")
    if not files:
        print("No file selected.")
        return

    failed = False
    for f in files:
        try:
            print(f"{f}  ->  {convert(f)}")
        except Exception as e:  # keep going so one bad file does not stop the rest
            failed = True
            print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
