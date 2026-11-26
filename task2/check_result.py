"""Compare a simulated edge-detection result against a Python Sobel reference.

usage: python3 check_result.py <source.pgm> <result.pgm>
Needs numpy; also writes a .png of the result if Pillow is installed.
All pixels are compared. Boundaries are mirrored (task 4a): a neighbour outside
the image is a copy of the nearest edge pixel.
|Dx| + |Dy| is scaled to 8 bits as ((mag >> 1) * 85) >> 8, as in the accelerator.
"""
import sys
import numpy as np


def read_pgm(path):
    lines = [l for l in open(path).read().split('\n') if not l.startswith('#')]
    t = ' '.join(lines).split()
    assert t[0] == 'P2', 'expected ASCII PGM (P2)'
    w, h = int(t[1]), int(t[2])
    return np.array([0 if v.lower().startswith('x') else int(v) for v in t[4:4 + w * h]],
                    dtype=np.int32).reshape(h, w)


def sobel(img):
    h, w = img.shape
    p = np.pad(img, 1, mode='edge')
    out = np.zeros_like(img)
    s = lambda row, d: row[1 + d:1 + d + w]
    for r in range(h):
        a, b, c = p[r], p[r + 1], p[r + 2]      # image rows r-1, r, r+1
        dx = (s(a, 1) - s(a, -1)) + 2 * (s(b, 1) - s(b, -1)) + (s(c, 1) - s(c, -1))
        dy = (s(a, -1) - s(c, -1)) + 2 * (s(a, 0) - s(c, 0)) + (s(a, 1) - s(c, 1))
        mag = np.abs(dx) + np.abs(dy)           # 0..1530
        out[r] = ((mag >> 1) * 85) >> 8
    return out


src, res = sys.argv[1], sys.argv[2]
exp, got = sobel(read_pgm(src)), read_pgm(res)
ok = np.array_equal(exp, got)
print("PASS: result matches Sobel reference" if ok else
      f"FAIL: {int((exp != got).sum())} pixels differ")
try:
    from PIL import Image
    for pgm, img in ((src, read_pgm(src)), (res, got)):
        png = pgm.replace('.pgm', '.png')
        Image.fromarray(img.astype(np.uint8)).save(png)
        print("wrote", png)
except ImportError:
    pass
sys.exit(0 if ok else 1)
