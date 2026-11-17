"""Bunker sand textures: pale warm sand, plain and with parallel rake lines."""
import math

from PIL import ImageDraw

from tex_kit import (SIZE, draw_dots, fbm, make_lut, paint, rng_for, save_texture)

SAND_RAMP = [(0.0, (178, 156, 114)), (0.5, (192, 172, 130)), (1.0, (206, 190, 152))]
GRAINS = [(160, 140, 100), (218, 204, 168), (184, 164, 122)]
RAKE_SPACING = 8  # divides SIZE, so the rake lines wrap cleanly


def _render_sand(texture_id):
    rng = rng_for(texture_id)
    lut = make_lut(SAND_RAMP)
    tone = fbm(rng, [(3, 1.0), (10, 0.5), (40, 0.2)])
    img = paint(lut, tone, rng=rng, speckle=0.10)
    draw_dots(img, rng, 42000, (0.5, 0.9), GRAINS, outline_shade=1.0)
    return img, rng


def _rake(img, rng):
    """Parallel rake lines: a dark groove with a light ridge beside it, gently wavy."""
    draw = ImageDraw.Draw(img)
    groove, ridge = (168, 148, 106), (206, 190, 150)
    for k in range(SIZE // RAKE_SPACING):
        y0 = k * RAKE_SPACING + rng.uniform(-0.6, 0.6)
        phase_a = rng.uniform(0, 2 * math.pi)
        phase_b = rng.uniform(0, 2 * math.pi)
        for colour, dy in ((groove, 0.0), (ridge, 2.0)):
            pts = []
            for x in range(0, SIZE + 1, 4):
                # Integer cycles per tile keep the waviness periodic in x.
                wave = 1.2 * math.sin(2 * math.pi * 2 * x / SIZE + phase_a) \
                    + 0.5 * math.sin(2 * math.pi * 5 * x / SIZE + phase_b)
                pts.append((x, y0 + dy + wave))
            for oy in (-SIZE, 0, SIZE):
                draw.line([(px, py + oy) for px, py in pts], fill=colour, width=1)


def build(out_dir):
    entries = []

    img, _ = _render_sand("bunker_sand")
    entries.append(save_texture(out_dir, "sand", "bunker_sand", img,
                                "Bunker sand: pale warm sand with fine speckle."))

    img, rng = _render_sand("bunker_sand_raked")
    _rake(img, rng)
    entries.append(save_texture(out_dir, "sand", "bunker_sand_raked", img,
                                "Raked bunker sand: same sand with parallel rake lines."))
    return entries
