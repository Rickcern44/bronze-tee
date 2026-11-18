"""Rock textures (Phase 1): rough grey stone, layered cliff strata, rounded cobbles."""
import math

from tex_kit import (SIZE, draw_shapes, draw_strokes, fbm, make_lut, paint, pick_colour,
                     rng_for, save_texture, smoothstep)



def _rock_grey(out_dir):
    rng = rng_for("rock_grey")
    lut = make_lut([(0.0, (96, 91, 84)), (0.5, (128, 122, 112)), (1.0, (160, 154, 142))])
    img = paint(lut, fbm(rng, [(4, 1.0), (10, 0.6), (32, 0.3)]), rng=rng, speckle=0.06)
    # Irregular facets: lit faces with a dark shadow edge down-right, so each facet has a real edge.
    lit = [(150, 144, 134), (164, 158, 148), (136, 130, 120)]
    draw_shapes(img, rng, 90, (16, 34), 6, lit, irregular=0.4, outline_shade=0.7, shadow=(3, 3, 0.55))
    dark = [(104, 99, 90), (118, 112, 102)]
    draw_shapes(img, rng, 60, (12, 22), 5, dark, irregular=0.35, outline_shade=0.7, shadow=(2, 2, 0.6))
    # Chips: small light and dark fragments.
    draw_shapes(img, rng, 420, (3, 9), 6, [(176, 170, 160), (90, 85, 78), (150, 144, 134)],
                irregular=0.35, outline_shade=0.7, shadow=(1, 1, 0.6))
    return save_texture(out_dir, "rock", "rock_grey", img,
                        "Rock grey: rough grey stone with soft facets and chips, light and dark variation.")


def _cliff_strata(out_dir):
    rng = rng_for("cliff_strata")
    band = 32  # 16 bands per tile; divides SIZE so the layers wrap
    values = [rng.uniform(0.0, 1.0) for _ in range(SIZE // band)]
    fine = fbm(rng, [(24, 1.0), (64, 0.4)])
    tone = []
    for i, f in enumerate(fine):
        y = i // SIZE
        pos = y / float(band)
        k = int(pos)
        frac = pos - k
        a = values[k % len(values)]
        b = values[(k + 1) % len(values)]
        # Hard-ish band edges: the transition occupies the last 30% of each band.
        t = smoothstep((frac - 0.7) / 0.3)
        tone.append(0.75 * (a + (b - a) * t) + 0.25 * f)
    lut = make_lut([(0.0, (120, 114, 102)), (0.5, (150, 144, 130)), (1.0, (176, 170, 156))])
    img = paint(lut, tone, rng=rng, speckle=0.04)
    # Cracks roughly along the layers.
    draw_strokes(img, rng, 700, (30, 80), (1,), 0.0, 0.08, pick_colour([(92, 88, 80), (110, 104, 94)]))
    return save_texture(out_dir, "rock", "cliff_strata", img,
                        "Cliff strata: horizontal layered bands in grey-beige with some cracks.")


def _cobble(out_dir):
    rng = rng_for("cobble")
    # Dark mortar base.
    lut = make_lut([(0.0, (52, 48, 44)), (0.5, (66, 62, 56)), (1.0, (80, 76, 68))])
    img = paint(lut, fbm(rng, [(8, 1.0), (24, 0.3)]), rng=rng, speckle=0.04)
    # 8x8 grid cells (64 px, divides SIZE), each stone jittered in position and size.
    centers = []
    for gy in range(8):
        for gx in range(8):
            centers.append((gx * 64 + 32 + rng.uniform(-7, 7), gy * 64 + 32 + rng.uniform(-7, 7)))
    stones = [(150, 144, 134), (168, 150, 118), (128, 122, 114), (176, 166, 150), (140, 128, 110)]
    # Light comes from the top-left: each stone casts a dark crescent down-right, no highlight disc.
    draw_shapes(img, rng, 0, (20, 28), 16, stones, aspect=0.9, irregular=0.08,
                outline_shade=0.72, shadow=(3, 4, 0.5), centers=centers)
    return save_texture(out_dir, "rock", "cobble", img,
                        "Cobble: rounded grey and tan stones with dark mortar gaps, each stone shaded.")


def build(out_dir):
    return [_rock_grey(out_dir), _cliff_strata(out_dir), _cobble(out_dir)]
