"""Water textures (Phase 1): deep water and shallow water."""
from PIL import Image

from tex_kit import (caustic_field, composite_field, draw_wave_segments, fbm, make_lut, paint,
                     rng_for, save_texture, shade)


def _deep(out_dir):
    rng = rng_for("water_deep")
    # Teal-blue, mid-dark: mean luma about 98.
    lut = make_lut([(0.0, (30, 92, 110)), (0.5, (44, 118, 134)), (1.0, (62, 140, 150))])
    tone = fbm(rng, [(2, 1.0), (4, 0.5), (12, 0.12)])
    img = paint(lut, tone, rng=rng, speckle=0.02)
    # Irregular ripple lines: varying length, wave and brightness.
    light = (72, 150, 160)
    draw_wave_segments(img, rng, 320, (30, 180), 2.5, (30, 90),
                       lambda r: shade(light, r.uniform(0.5, 1.0)))
    return save_texture(out_dir, "water", "water_deep", img,
                        "Deep water: teal-blue, large soft undulation, irregular faint ripple lines.")


def _shallow(out_dir):
    rng = rng_for("water_shallow")
    lut = make_lut([(0.0, (62, 140, 150)), (0.5, (90, 166, 164)), (1.0, (116, 188, 176))])
    tone = fbm(rng, [(4, 1.0), (10, 0.4), (32, 0.12)])
    img = paint(lut, tone, rng=rng, speckle=0.03)
    # Soft caustic network: thin bright ridges of a noise field, blended at partial strength.
    ridges = caustic_field(fbm(rng, [(10, 1.0), (22, 0.5)]), power=10.0)
    glow = Image.new("RGB", img.size, (176, 228, 216))
    img = composite_field(img, glow, [0.5 * c for c in ridges], gamma=1.0)
    # Finer, irregular ripple lines.
    draw_wave_segments(img, rng, 520, (20, 120), 1.6, (16, 48),
                       lambda r: shade((170, 222, 210), r.uniform(0.55, 1.0)))
    return save_texture(out_dir, "water", "water_shallow", img,
                        "Shallow water: lighter bluish-green, finer irregular ripples, soft caustic lines.")


def build(out_dir):
    return [_deep(out_dir), _shallow(out_dir)]
