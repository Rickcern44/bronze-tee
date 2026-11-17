"""Ground textures: brown pebbly dirt, grey-beige gravel path, and warm-grey cart path."""
import math

from tex_kit import (draw_dots, draw_strokes, draw_walks, fbm, make_lut, paint, rng_for,
                     save_texture, stroke_colour)

ROCK_GREYS = [(179, 172, 158), (138, 132, 120)]  # from the palette: B3AC9E / 8A8478


def build(out_dir):
    entries = []

    # Dirt: brown base with clumps and pebbles.
    rng = rng_for("dirt")
    lut = make_lut([(0.0, (92, 62, 42)), (0.5, (120, 84, 56)), (1.0, (150, 110, 74))])
    img = paint(lut, fbm(rng, [(3, 1.0), (9, 0.6), (30, 0.3)]), rng=rng, speckle=0.08)
    draw_strokes(img, rng, 30000, (3, 8), (1, 2), 0.0, math.pi,
                 stroke_colour(lut, 0.05, 0.95))
    draw_dots(img, rng, 900, (1.2, 3.2), ROCK_GREYS + [(70, 46, 30), (150, 120, 90)])
    entries.append(save_texture(out_dir, "ground", "dirt", img,
                                "Dirt: brown, pebbly; rough edges and off-course ground."))

    # Gravel path: grey-beige base with small rimmed stones.
    rng = rng_for("gravel_path")
    lut = make_lut([(0.0, (120, 114, 102)), (0.5, (150, 144, 132)), (1.0, (176, 170, 156))])
    img = paint(lut, fbm(rng, [(4, 1.0), (12, 0.5)]), rng=rng, speckle=0.06)
    draw_dots(img, rng, 2600, (2.0, 5.0),
              [(179, 172, 158), (138, 132, 120), (160, 152, 138), (112, 106, 98), (190, 184, 170)],
              outline_shade=0.7)
    entries.append(save_texture(out_dir, "ground", "gravel_path", img,
                                "Gravel path: grey-beige small stones."))

    # Cart path: smooth warm-grey concrete/asphalt with faint cracks and speckle.
    rng = rng_for("cart_path")
    lut = make_lut([(0.0, (138, 134, 126)), (0.5, (148, 144, 136)), (1.0, (156, 152, 144))])
    img = paint(lut, fbm(rng, [(12, 1.0), (40, 0.5)]), rng=rng, speckle=0.10)
    draw_walks(img, rng, 6, 40, 9.0, (128, 124, 116), width=1)
    draw_dots(img, rng, 12000, (0.5, 0.9), [(120, 116, 108), (176, 172, 164)], outline_shade=0.9)
    entries.append(save_texture(out_dir, "ground", "cart_path", img,
                                "Cart path: smooth warm-grey concrete with faint cracks."))
    return entries
