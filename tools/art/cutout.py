# /// script
# dependencies = ["pillow", "numpy", "scipy"]
# ///
"""Cut painted sprites out of generated images.

Flood-fills near-white from the image border (interior whites survive),
splits the picture into separate pieces (sprite sheets), saves each trimmed.

  uv run cutout.py in.png out_prefix [--min 2000] [--tol 28] [--gap 6]

Writes out_prefix_0.png ... in reading order and prints each size.
"""
import argparse
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("prefix")
ap.add_argument("--min", type=int, default=2000, help="smallest piece in pixels")
ap.add_argument("--tol", type=int, default=28, help="how far from white still counts as background")
ap.add_argument("--gap", type=int, default=6, help="pieces closer than this many pixels stay together")
ap.add_argument("--pad", type=int, default=4)
a = ap.parse_args()

img = Image.open(a.src).convert("RGBA")
rgb = np.asarray(img)[..., :3].astype(int)
near_white = (255 - rgb).max(axis=2) <= a.tol
lab, _ = ndimage.label(near_white)
border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
bg = np.isin(lab, border[border > 0])
fg = ~bg

groups, _ = ndimage.label(ndimage.binary_dilation(fg, iterations=a.gap))
found = []
for i, sl in enumerate(ndimage.find_objects(groups), 1):
    if sl is not None and (fg[sl] & (groups[sl] == i)).sum() >= a.min:
        found.append((i, sl))
row_h = max(1, img.height // 4)
found.sort(key=lambda t: ((t[1][0].start + t[1][0].stop) // 2 // row_h, t[1][1].start))

for k, (i, sl) in enumerate(found):
    y0, y1 = max(0, sl[0].start - a.pad), min(img.height, sl[0].stop + a.pad)
    x0, x1 = max(0, sl[1].start - a.pad), min(img.width, sl[1].stop + a.pad)
    mask = fg[y0:y1, x0:x1] & (groups[y0:y1, x0:x1] == i)
    alpha = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    piece = img.crop((x0, y0, x1, y1))
    piece.putalpha(alpha)
    path = f"{a.prefix}_{k}.png"
    piece.save(path)
    print(f"{path} {piece.width}x{piece.height}")
