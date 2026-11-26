# /// script
# dependencies = ["pillow"]
# ///
"""Contact sheet of candidates: uv run contact.py name [name...] -> out/sheet_<names>.png"""
import sys, glob, os
from PIL import Image, ImageDraw

os.chdir(os.path.dirname(os.path.abspath(__file__)))
names = sys.argv[1:]
rows = []
for n in names:
    files = sorted(glob.glob(f"out/raw/{n}_*.png"))
    rows.append(files)
cell = 320
cols = max(len(r) for r in rows)
sheet = Image.new("RGB", (cols * cell, len(rows) * (cell + 20)), (60, 60, 60))
d = ImageDraw.Draw(sheet)
for y, r in enumerate(rows):
    for x, f in enumerate(r):
        im = Image.open(f).convert("RGB")
        im.thumbnail((cell, cell))
        sheet.paste(im, (x * cell, y * (cell + 20) + 20))
        d.text((x * cell + 4, y * (cell + 20) + 4), os.path.basename(f), fill=(255, 255, 0))
out = f"out/sheet_{'_'.join(names)}.png"
sheet.save(out)
print(out)
