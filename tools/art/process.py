# /// script
# dependencies = ["pillow", "numpy", "scipy"]
# ///
"""Turn picked candidates into WoW-ready 32-bit uncompressed TGAs.

  uv run tools/art/process.py          # all
  uv run tools/art/process.py ghoul    # only some

Picks are in PICKS below (name -> (seed, size, kind)).
sprite: flood-fill white from the border -> alpha (interior whites survive), drop specks,
        1px feather, trim, pad square with margin, Lanczos resize (premultiplied).
glow:   black background; alpha = brightness, colour un-premultiplied (works with ADD and BLEND).
tile:   half-offset blend to make it seamless, darken + lower contrast, resize.
"""
import sys, os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "..", "AzerothSurvivors", "Art")
RAW = os.path.join(HERE, "out", "raw")

PICKS = {
    "ghoul":  (1104, 64, "sprite"),
    "bat":    (1203, 64, "sprite"),
    "wraith": (1302, 64, "sprite"),
    "brute":  (1403, 128, "sprite"),
    "elite":  (1502, 128, "sprite"),
    "boss":   (1603, 256, "sprite"),
    "hero":   (1703, 64, "sprite"),
    "gem":    (1801, 32, "sprite"),
    "potion": (1903, 32, "sprite"),
    "bolt":   (2013, 32, "glow"),
    "orb":    (2101, 64, "glow"),
    "ground": (2204, 256, "tile"),
    "hero_rogue": (2302, 64, "sprite"),
    "hero_druid": (2403, 64, "sprite"),
    "knife":    (2501, 32, "sprite"),
    "shuriken": (2604, 32, "sprite"),
    "hammer":   (2702, 32, "sprite"),
    "shield":   (2811, 64, "sprite"),
    "wrath":    (2901, 32, "glow"),
    "star":     (3004, 64, "glow"),
    "slash":    ("proc", 128, "glow"),  # procedural: uv run tools/art/slash_proc.py -> out/raw/slash_proc.png
}
BOOST = {"bat": 1.5, "hero_rogue": 1.3, "shuriken": 1.6, "knife": 1.3}  # brightness multiplier per sprite
TOL = {"shield": 110}  # wider near-white tolerance: eats the pale glow halo that would leave a cream ring
MARGIN = 0.04  # fraction of final size left empty on each side


def square_resize(img, size, margin=MARGIN):
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    img = img.crop(bbox)
    side = int(max(img.size) / (1 - 2 * margin)) + 1
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS, reducing_gap=3.0)


def sprite(src, size, tol=30, boost=1.0):
    img = Image.open(src).convert("RGB")
    rgb = np.asarray(img).astype(int)
    near_white = (255 - rgb).max(axis=2) <= tol
    lab, _ = ndimage.label(near_white)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    fg = ~np.isin(lab, border[border > 0])
    # enclosed holes of flat pure-white background (e.g. between arm and body) are background too
    holes, nh = ndimage.label(near_white & fg)
    for i, sl in enumerate(ndimage.find_objects(holes), 1):
        m = holes[sl] == i
        if m.sum() > 40 and rgb[sl][m].min(axis=1).mean() > 240:
            fg[sl][m] = False
    # keep components that are at least 2% of the largest one (drop specks)
    comp, n = ndimage.label(fg)
    if n:
        sizes = ndimage.sum(fg, comp, range(1, n + 1))
        keep = np.isin(comp, 1 + np.nonzero(sizes >= sizes.max() * 0.02)[0])
        fg = keep
    fg = ndimage.binary_erosion(fg, iterations=2)  # eat the light fringe
    alpha = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))
    rgba = img.convert("RGBA")
    rgba.putalpha(alpha)
    if boost != 1.0:  # lift very dark sprites so they read on the dark ground
        from PIL import ImageEnhance
        rgb_only = ImageEnhance.Brightness(rgba.convert("RGB")).enhance(boost)
        rgb_only = ImageEnhance.Color(rgb_only).enhance(1.25)
        rgb_only.putalpha(rgba.getchannel("A"))
        rgba = rgb_only
    out = square_resize(rgba, size)
    if size <= 64:
        out = out.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
    return out


def glow(src, size):
    img = Image.open(src).convert("RGB")
    a = np.asarray(img).astype(np.float32) / 255
    lum = a.max(axis=2)
    lum = np.clip((lum - 0.04) / 0.96, 0, 1)  # crush the near-black haze
    # fade to zero towards the square border so no hard edge survives
    h, w = lum.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    lum *= np.clip((1.0 - r) / 0.15, 0, 1)
    col = np.clip(a / np.maximum(a.max(axis=2, keepdims=True), 1e-4), 0, 1)
    rgba = np.dstack([col, lum]) * 255
    im = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    return square_resize(im, size, margin=0.02)


def tile(src, size):
    img = Image.open(src).convert("RGB")
    s = img.width * 3 // 16  # use the central 5/8 so features stay readable at 256
    img = img.crop((s, s, img.width - s, img.height - s))
    img = img.resize((512, 512), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32)
    n = a.shape[0]
    b = np.roll(a, (n // 2, n // 2), axis=(0, 1))
    t = np.abs(np.linspace(-1, 1, n))  # 1 at edges, 0 centre
    edge = np.maximum.outer(t, t)  # how close to any edge
    wB = np.clip((edge - 0.55) / 0.35, 0, 1)[..., None]  # use offset copy near edges
    m = a * (1 - wB) + b * wB
    # darken and reduce contrast so sprites read on top
    mean = m.mean(axis=(0, 1), keepdims=True)
    m = (m - mean) * 0.7 + mean
    m = m * 0.72
    im = Image.fromarray(np.clip(m, 0, 255).astype(np.uint8), "RGB").resize((size, size), Image.LANCZOS)
    return im.convert("RGBA")


def save_tga(im, path):
    im.convert("RGBA").save(path, format="TGA", rle=False)
    hdr = open(path, "rb").read(18)
    chk = Image.open(path)
    assert hdr[2] == 2 and hdr[16] == 32 and chk.mode == "RGBA", (path, hdr)
    w, h = chk.size
    assert w == h and w & (w - 1) == 0
    print(f"{os.path.basename(path)} {w}x{h} {chk.mode} type={hdr[2]} bpp={hdr[16]} desc=0x{hdr[17]:02x} bytes={os.path.getsize(path)}")


def main():
    os.makedirs(ART, exist_ok=True)
    names = sys.argv[1:] or list(PICKS)
    for n in names:
        seed, size, kind = PICKS[n]
        src = os.path.join(RAW, f"{n}_{seed}.png")
        if kind == "sprite":
            im = sprite(src, size, tol=TOL.get(n, 30), boost=BOOST.get(n, 1.0))
        else:
            im = {"glow": glow, "tile": tile}[kind](src, size)
        im.save(os.path.join(HERE, "out", f"final_{n}.png"))
        save_tga(im, os.path.join(ART, f"{n}.tga"))


if __name__ == "__main__":
    main()
