"""Compare a simulated edge-detection result against a Python Sobel reference.

usage: python3 check_result.py <source.pgm> <result.pgm>
Needs numpy; also writes a .png of the result if Pillow is installed.
Rows 0 and 287 are not processed (task 1: boundaries ignored) and are not compared.
Left/right columns are computed against zero padding, as in the accelerator.
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
    p = np.pad(img, ((0, 0), (1, 1)))
    out = np.zeros_like(img)
    s = lambda row, d: row[1 + d:1 + d + w]
    for r in range(1, h - 1):
        a, b, c = p[r - 1], p[r], p[r + 1]
        dx = (s(a, 1) - s(a, -1)) + 2 * (s(b, 1) - s(b, -1)) + (s(c, 1) - s(c, -1))
        dy = (s(a, -1) - s(c, -1)) + 2 * (s(a, 0) - s(c, 0)) + (s(a, 1) - s(c, 1))
        out[r] = np.minimum(np.abs(dx) + np.abs(dy), 255)
    return out


src, res = sys.argv[1], sys.argv[2]
exp, got = sobel(read_pgm(src)), read_pgm(res)
ok = np.array_equal(exp[1:-1], got[1:-1])
print("PASS: result matches Sobel reference" if ok else
      f"FAIL: {int((exp[1:-1] != got[1:-1]).sum())} pixels differ")
try:
    from PIL import Image
    for pgm, img in ((src, read_pgm(src)), (res, got)):
        png = pgm.replace('.pgm', '.png')
        Image.fromarray(img.astype(np.uint8)).save(png)
        print("wrote", png)
except ImportError:
    pass
sys.exit(0 if ok else 1)
