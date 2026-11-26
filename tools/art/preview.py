# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Composite final TGAs at in-game sizes over the 3x3-tiled ground -> out/preview.png (+ out/preview_2x.png, out/ground_3x3.png)."""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "..", "AzerothSurvivors", "Art")
load = lambda n: Image.open(os.path.join(ART, f"{n}.tga")).convert("RGBA")

g = load("ground").convert("RGB")
bg = Image.new("RGB", (768, 768))
for y in range(3):
    for x in range(3):
        bg.paste(g, (x * 256, y * 256))
bg.save(os.path.join(HERE, "out", "ground_3x3.png"))

canvas = bg.copy().convert("RGBA")
# (name, display px, x, y, additive)
items = [
    ("hero", 48, 384, 384, False),
    ("ghoul", 40, 250, 300, False), ("ghoul", 40, 520, 290, False), ("ghoul", 32, 300, 470, False),
    ("bat", 32, 460, 220, False), ("bat", 28, 200, 420, False),
    ("wraith", 40, 560, 470, False), ("wraith", 36, 160, 230, False),
    ("brute", 72, 620, 360, False), ("elite", 72, 130, 560, False),
    ("boss", 144, 600, 640, False),
    ("gem", 16, 330, 400, False), ("gem", 16, 440, 430, False), ("gem", 20, 360, 540, False),
    ("potion", 24, 470, 560, False),
    ("bolt", 16, 430, 350, True), ("bolt", 16, 470, 330, True), ("bolt", 20, 300, 360, True),
    ("orb", 48, 330, 300, True), ("orb", 40, 420, 470, True),
    # class update: rogue + druid heroes and their weapons
    ("hero_rogue", 48, 120, 110, False), ("hero_druid", 48, 660, 110, False),
    ("knife", 24, 170, 110, False), ("knife", 24, 200, 140, False),
    ("shuriken", 20, 90, 170, False), ("shuriken", 20, 150, 180, False),
    ("hammer", 24, 430, 400, False), ("shield", 32, 384, 330, False),
    ("wrath", 20, 610, 120, True), ("wrath", 20, 600, 170, True),
    ("star", 40, 700, 220, True), ("star", 32, 640, 260, True),
    ("slash", 64, 250, 110, True),
]
for name, px, cx, cy, add in items:
    s = load(name).resize((px, px), Image.LANCZOS)
    x, y = cx - px // 2, cy - px // 2
    if add:  # WoW ADD blend: dst + src*alpha
        reg = np.asarray(canvas.crop((x, y, x + px, y + px))).astype(np.float32)
        a = np.asarray(s).astype(np.float32)
        reg[..., :3] = np.clip(reg[..., :3] + a[..., :3] * a[..., 3:] / 255, 0, 255)
        canvas.paste(Image.fromarray(reg.astype(np.uint8), "RGBA"), (x, y))
    else:
        canvas.alpha_composite(s, (x, y))
canvas = canvas.convert("RGB")
canvas.save(os.path.join(HERE, "out", "preview.png"))
canvas.resize((1536, 1536), Image.NEAREST).save(os.path.join(HERE, "out", "preview_2x.png"))

# native-size strip of every sprite on the ground, 4x nearest for inspection
names = ["hero", "hero_rogue", "hero_druid", "ghoul", "bat", "wraith", "brute", "elite", "boss", "gem", "potion",
         "bolt", "orb", "knife", "shuriken", "hammer", "shield", "wrath", "star", "slash"]
W = sum(load(n).width + 8 for n in names)
strip = Image.new("RGBA", (W, 264))
for x in range(0, W, 256):
    strip.paste(g, (x, 0))
x = 4
for n in names:
    s = load(n)
    strip.alpha_composite(s, (x, 4))
    x += s.width + 8
strip.convert("RGB").save(os.path.join(HERE, "out", "native_strip.png"))
print("out/preview.png out/preview_2x.png out/ground_3x3.png out/native_strip.png")
