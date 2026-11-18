"""Ground cover textures (Phase 1): mud, leaf litter, pine needles, moss, wildflower meadow."""
import math

from tex_kit import (composite_field, draw_dots, draw_shapes, draw_strokes, fbm, make_lut,
                     paint, pick_colour, rng_for, save_texture, smoothstep, stroke_colour)

UPRIGHT = math.pi / 2


def _mud(out_dir):
    rng = rng_for("mud")
    lut = make_lut([(0.0, (58, 44, 34)), (0.5, (84, 64, 46)), (1.0, (104, 80, 58))])
    img = paint(lut, fbm(rng, [(3, 1.0), (9, 0.5), (30, 0.2)]), rng=rng, speckle=0.03)
    # Small, sharper puddle sheen: a higher-frequency field thresholded into small patches.
    sheen_field = fbm(rng, [(10, 1.0), (24, 0.4)])
    sheen_mask = [0.5 * smoothstep((v - 0.7) * 14.0) for v in sheen_field]
    sheen = paint(make_lut([(0.0, (74, 92, 102)), (1.0, (112, 130, 140))]),
                  fbm(rng, [(16, 1.0)]), rng=rng, speckle=0.02)
    img = composite_field(img, sheen, sheen_mask, gamma=1.0)
    return save_texture(out_dir, "cover", "mud", img,
                        "Mud: dark wet brown, smooth, with soft puddle sheen patches.")


def _leaf_litter(out_dir):
    rng = rng_for("leaf_litter")
    lut = make_lut([(0.0, (48, 36, 24)), (0.5, (70, 50, 32)), (1.0, (90, 64, 40))])
    img = paint(lut, fbm(rng, [(4, 1.0), (14, 0.4)]), rng=rng, speckle=0.05)
    leaves = [(156, 94, 44), (190, 122, 52), (212, 160, 78), (132, 78, 40), (170, 110, 50),
              (196, 140, 66)]
    draw_shapes(img, rng, 2200, (4.0, 7.0), 12, leaves, aspect=0.5, irregular=0.12,
                outline_shade=0.7, shadow=(1, 1, 0.5))
    return save_texture(out_dir, "cover", "leaf_litter", img,
                        "Leaf litter: overlapping small oval leaves in browns and ochre over dark ground.")


def _pine_needles(out_dir):
    rng = rng_for("pine_needles")
    lut = make_lut([(0.0, (74, 50, 30)), (0.5, (100, 68, 40)), (1.0, (126, 88, 50))])
    img = paint(lut, fbm(rng, [(6, 1.0), (20, 0.3)]), rng=rng, speckle=0.04)
    needles = [(140, 96, 54), (164, 118, 66), (118, 80, 44), (186, 140, 84), (96, 62, 36)]
    # Random directions: a full circle of angles, short thin strokes.
    draw_strokes(img, rng, 110000, (8, 14), (1,), 0.0, math.pi, pick_colour(needles))
    return save_texture(out_dir, "cover", "pine_needles", img,
                        "Pine needles: dense fine straight needles in warm browns, random directions.")


def _moss(out_dir):
    rng = rng_for("moss")
    lut = make_lut([(0.0, (40, 96, 44)), (0.5, (70, 130, 58)), (1.0, (96, 156, 72))])
    img = paint(lut, fbm(rng, [(6, 1.0), (14, 0.6), (40, 0.3)]), rng=rng, speckle=0.03)
    tips = [(130, 186, 96), (108, 170, 84), (150, 200, 110)]
    draw_dots(img, rng, 9000, (1.2, 3.0), tips, outline_shade=0.9)
    return save_texture(out_dir, "cover", "moss", img,
                        "Moss: soft clumpy mottled green with lighter tips.")


def _wildflower_meadow(out_dir):
    rng = rng_for("wildflower_meadow")
    lut = make_lut([(0.0, (96, 160, 72)), (0.5, (120, 182, 86)), (1.0, (140, 198, 100))])
    img = paint(lut, fbm(rng, [(4, 1.0), (12, 0.5)]), rng=rng, speckle=0.03)
    draw_strokes(img, rng, 60000, (5, 10), (1, 2), UPRIGHT, 0.8, stroke_colour(lut, 0.1, 0.9))
    # Sparse flower dots, one colour group at a time.
    draw_dots(img, rng, 700, (2.4, 3.4), [(240, 120, 176)], outline_shade=0.8)
    draw_dots(img, rng, 500, (2.2, 3.0), [(255, 206, 84)], outline_shade=0.8)
    draw_dots(img, rng, 320, (2.0, 2.8), [(250, 250, 244)], outline_shade=0.9)
    return save_texture(out_dir, "cover", "wildflower_meadow", img,
                        "Wildflower meadow: green grass with sparse pink, yellow and white flowers.")


def build(out_dir):
    return [_mud(out_dir), _leaf_litter(out_dir), _pine_needles(out_dir),
            _moss(out_dir), _wildflower_meadow(out_dir)]
