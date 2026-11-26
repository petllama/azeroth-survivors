# Azeroth Survivors art pipeline

Sprites in `AzerothSurvivors/Art/*.tga` are generated with the local image model
(SwarmUI, FLUX 3 Klein Q8, `imagine -m flux --raw`, 1024x1024, 16 steps, cfg 1; no LLM prompt upsampler).

    swarmui-up
    tools/art/gen.sh [name...]      # 4 candidates per line of prompts.txt -> out/raw/<name>_<seed>.png
    uv run tools/art/contact.py ghoul bat    # contact sheet -> out/sheet_*.png
    uv run tools/art/process.py [name...]   # picked seed -> Art/<name>.tga (verifies TGA header)
    uv run tools/art/slash_proc.py          # procedural slash.tga source (no model)
    uv run tools/art/preview.py             # out/preview.png, out/ground_3x3.png, out/native_strip.png
    systemctl --user stop swarmui flux3-pup

`out/` is git-ignored. Seeds are deterministic: candidate `<name>_<seed>` came from `--seed <first> -n 4`
(SwarmUI increments the seed per image), so rerunning `gen.sh <name>` reproduces them.

## Prompt = subject (prompts.txt) + shared style block (gen.sh)

- sprite: `<subject>. dark-fantasy World of Warcraft inspired hand-painted game sprite, viewed from a slightly
  top-down three-quarter angle, bold readable silhouette, thick dark outline, saturated colours, single centered
  subject, full body uncropped with generous margin around it, plain flat pure white background, no text, no
  ground shadow, isolated game asset`
- glow: `<subject>. dark-fantasy World of Warcraft inspired hand-painted spell effect game sprite, single centered
  subject with generous margin, bright luminous glow, plain pure black background, no text, isolated game asset`
- tile: `<subject>. hand-painted dark-fantasy World of Warcraft style game ground texture, painterly`

## Picks

| file | size | picked seed | kind | notes |
|---|---|---|---|---|
| ghoul.tga | 64 | 1104 | sprite | |
| bat.tga | 64 | 1203 | sprite | brightness x1.5, saturation x1.25 so it reads on the dark ground |
| wraith.tga | 64 | 1302 | sprite | |
| brute.tga | 128 | 1403 | sprite | |
| elite.tga | 128 | 1502 | sprite | |
| boss.tga | 256 | 1603 | sprite | enclosed white hole between arm and body removed |
| hero.tga | 64 | 1703 | sprite | |
| gem.tga | 32 | 1801 | sprite | light desaturated cyan (game tints it) |
| potion.tga | 32 | 1903 | sprite | |
| bolt.tga | 32 | 2013 | glow | second prompt ("round spherical"); seeds 2001-2004 were eye-shaped |
| orb.tga | 64 | 2101 | glow | |
| ground.tga | 256 | 2204 | tile | central 5/8 crop, half-offset blend -> seamless, contrast x0.7, brightness x0.72 |
| hero_rogue.tga | 64 | 2302 | sprite | brightness x1.3 (dark purple/black leather vanishes on the ground otherwise) |
| hero_druid.tga | 64 | 2403 | sprite | tall/thin silhouette (antlers + staff) so the body is narrower than hero.tga |
| knife.tga | 32 | 2501 | sprite | blade points right (+x); long thin object -> only ~5 px tall at 32; brightness x1.3 |
| shuriken.tga | 32 | 2604 | sprite | brightness x1.6 (dark steel on dark ground) |
| hammer.tga | 32 | 2702 | sprite | head up; thin handle is small at 32 |
| shield.tga | 64 | 2811 | sprite | second prompt ("perfectly circular buckler"); seeds 2801-2804 were heater shields. tol 110 so the pale glow halo is cut instead of leaving a cream ring (glow therefore not baked in) |
| wrath.tga | 32 | 2901 | glow | green rim, yellow-white core |
| star.tga | 64 | 3004 | glow | tail points up, head at the bottom of the (centred) square, not at its centre |
| slash.tga | 128 | proc | glow | procedural (`uv run tools/art/slash_proc.py` -> out/raw/slash_proc.png): model seeds 3101-3104 gave flat elliptical swooshes, not a right-bulging crescent. Thick edge on the right, horns tapering top-left/bottom-left |

## Processing (process.py)

Per-sprite knobs in process.py: `BOOST` (brightness x, saturation x1.25) and `TOL` (near-white cutout tolerance, default 30).

- sprite: flood-fill near-white (tol 30) from the border -> background; enclosed flat pure-white holes
  (>40 px, mean min channel > 240) also background; drop specks < 2% of the main body; erode 2 px, 1 px
  Gaussian feather; trim, pad to square with 4% margin, Lanczos resize (premultiplied); light unsharp mask at <= 64 px.
- glow: alpha = max(r,g,b) (black floor crushed, radial fade to 0 at the frame edge), colour un-premultiplied,
  so it looks the same with `SetBlendMode("ADD")` and normal `BLEND`.
- All outputs: 32-bit uncompressed TGA (type 2, 32 bpp, 8 alpha bits, bottom-left origin), power-of-two square.
