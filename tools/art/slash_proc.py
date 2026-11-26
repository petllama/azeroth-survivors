# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Procedural sword-swing crescent on black -> out/raw/slash_proc.png (1024x1024, glow kind).

A crescent = outer circle minus an inner circle shifted left, so the thick part bulges to the RIGHT (+x)
and the two horns taper to points top-left and bottom-left. Soft falloff + a faint blue rim; process.py
turns brightness into alpha like the other glow sprites.
"""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
N = 1024
y, x = (np.mgrid[0:N, 0:N].astype(np.float32) + 0.5) / N * 2 - 1  # [-1, 1]
R, cx = 0.78, -0.18                 # outer circle (centred slightly left so the arc fills the frame)
r2, dx = 0.80, -0.24                # inner circle, shifted left -> crescent thickness ~0.18 at the right
d_out = R - np.hypot(x - cx, y)      # >0 inside the outer circle
d_in = np.hypot(x - cx - dx, y) - r2  # >0 outside the inner circle
sd = np.minimum(d_out, d_in)         # signed distance-ish: >0 inside the crescent
edge = np.clip(sd / 0.012 + 0.5, 0, 1)            # anti-aliased crescent mask (~6 px ramp)
# leading (outer) edge hottest, fading toward the inner edge like a motion trail
body = edge * (0.55 + 0.45 * np.clip(1 - d_out / 0.20, 0, 1))
core = body
halo = np.exp(-np.maximum(-sd, 0) / 0.04)              # soft glow, continuous with the body
# thickest at the right, fade the horns (trail end) a bit: weight by x
fade = np.clip((x - cx + R * 0.95) / (R * 0.9), 0, 1) ** 0.6
white = core * fade
glow = halo * fade * 0.5
rgb = np.zeros((N, N, 3), np.float32)
rgb = np.maximum(white[..., None] * np.array([1.0, 1.0, 1.0]), glow[..., None] * np.array([0.55, 0.75, 1.0]))
img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
os.makedirs(os.path.join(HERE, "out", "raw"), exist_ok=True)
p = os.path.join(HERE, "out", "raw", "slash_proc.png")
img.save(p)
print(p)
