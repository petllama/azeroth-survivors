# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""0.6 set check: native-size strip of the new sprites next to existing heroes / ghoul.tga on every ground (glows drawn ADD)
-> out/native_strip_06.png (+ out/native_strip_06_2x.png nearest-upscaled)."""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "..", "AzerothSurvivors", "Art")
OUT = os.path.join(HERE, "out")
load = lambda n: Image.open(os.path.join(ART, f"{n}.tga")).convert("RGBA")

SPRITES = ["hero", "hero_warlock", "hero_dk", "ghoul", "dk_ghoul"]  # hero, hero_warlock, ghoul: existing, for scale/contrast
GLOWS = ["deathcoil", "dnd", "howlingblast", "blizzard"]
GROUNDS = ["ground", "ground_tirisfal", "ground_barrens", "ground_elwynn", "ground_snow"]

names = SPRITES + GLOWS
W = sum(load(n).width + 6 for n in names) + 6
rows = []
for g in GROUNDS:
    t = load(g).convert("RGBA")
    row = Image.new("RGBA", (W, 76))
    for x in range(0, W, 256):
        row.paste(t, (x, 0))
    x = 6
    for n in names:
        s = load(n)
        y = 6 + (64 - s.height) // 2
        if n in GLOWS:  # WoW ADD blend
            reg = np.asarray(row.crop((x, y, x + s.width, y + s.height))).astype(np.float32)
            a = np.asarray(s).astype(np.float32)
            reg[..., :3] = np.clip(reg[..., :3] + a[..., :3] * a[..., 3:] / 255, 0, 255)
            row.paste(Image.fromarray(reg.astype(np.uint8), "RGBA"), (x, y))
        else:
            row.alpha_composite(s, (x, y))
        x += s.width + 6
    rows.append(row)
strip = Image.new("RGB", (W, 76 * len(rows)))
for i, r in enumerate(rows):
    strip.paste(r.convert("RGB"), (0, 76 * i))
strip.save(os.path.join(OUT, "native_strip_06.png"))
strip.resize((W * 2, strip.height * 2), Image.NEAREST).save(os.path.join(OUT, "native_strip_06_2x.png"))
print("out/native_strip_06.png out/native_strip_06_2x.png")
