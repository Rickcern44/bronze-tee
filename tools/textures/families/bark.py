"""Bark textures (Phase 1): oak furrows, pine plates, birch with lenticels."""
from tex_kit import (composite_field, draw_shapes, draw_strokes, fbm, make_lut, paint,
                     pick_colour, rng_for, save_texture, smoothstep)

VERTICAL = 1.5707963267948966  # pi / 2


def _bark_oak(out_dir):
    rng = rng_for("bark_oak")
    lut = make_lut([(0.0, (46, 32, 22)), (0.5, (66, 46, 30)), (1.0, (88, 62, 40))])
    img = paint(lut, fbm(rng, [(4, 1.0), (12, 0.4)]), rng=rng, speckle=0.05)
    # Deep vertical furrows (dark) between raised ridges (light), long and wrapped.
    draw_strokes(img, rng, 16000, (30, 80), (2, 3), VERTICAL, 0.06,
                 pick_colour([(34, 24, 16), (50, 36, 24)]))
    draw_strokes(img, rng, 14000, (30, 70), (2, 4), VERTICAL, 0.05,
                 pick_colour([(104, 76, 50), (118, 88, 58)]))
    return save_texture(out_dir, "bark", "bark_oak", img,
                        "Oak bark: deep dark-brown vertical furrows and ridges.")


def _bark_pine(out_dir):
    rng = rng_for("bark_pine")
    # Dark gaps between plates.
    lut = make_lut([(0.0, (60, 34, 24)), (0.5, (78, 44, 30)), (1.0, (96, 56, 36))])
    img = paint(lut, fbm(rng, [(6, 1.0), (16, 0.3)]), rng=rng, speckle=0.05)
    # Irregular reddish-brown flakes with darker rims: varied sizes, stretched vertically.
    plates = [(136, 70, 46), (118, 58, 40), (150, 82, 52), (104, 50, 34)]
    draw_shapes(img, rng, 170, (24, 42), 7, plates, aspect=1.5, irregular=0.3, outline_shade=0.6,
                shadow=(2, 2, 0.6), upright=True)
    draw_shapes(img, rng, 300, (9, 18), 6, plates, aspect=1.3, irregular=0.3, outline_shade=0.6,
                shadow=(1, 1, 0.6), upright=True)
    return save_texture(out_dir, "bark", "bark_pine", img,
                        "Pine bark: broad flaky reddish-brown plates with darker gaps.")


def _bark_birch(out_dir):
    rng = rng_for("bark_birch")
    lut = make_lut([(0.0, (200, 192, 174)), (0.5, (218, 210, 192)), (1.0, (232, 226, 210))])
    img = paint(lut, fbm(rng, [(4, 1.0), (12, 0.4)]), rng=rng, speckle=0.03)
    # Soft grey patches where a low-frequency field peaks.
    patch_field = fbm(rng, [(3, 1.0), (8, 0.4)])
    patch_mask = [0.55 * smoothstep((v - 0.58) * 5.0) for v in patch_field]
    grey = paint(make_lut([(0.0, (150, 146, 140)), (1.0, (172, 168, 160))]),
                 fbm(rng, [(6, 1.0)]), rng=rng, speckle=0.02)
    img = composite_field(img, grey, patch_mask)
    # Horizontal dark lenticel marks.
    draw_strokes(img, rng, 1600, (6, 18), (2,), 0.0, 0.05,
                 pick_colour([(70, 64, 58), (96, 90, 84)]))
    return save_texture(out_dir, "bark", "bark_birch", img,
                        "Birch bark: pale cream-white with horizontal dark lenticel marks and grey patches.")


def build(out_dir):
    return [_bark_oak(out_dir), _bark_pine(out_dir), _bark_birch(out_dir)]
