"""Turf textures: fairways, cuts, collar, green, deep rough and native fescue.

Brightness order: green > collar > fairway_light > first_cut > fairway_dark > second_cut
> native_fescue > deep_rough. Green is finest and smoothest; deep_rough is darkest and coarsest.
"""
import math

from tex_kit import (draw_strokes, fbm, make_lut, paint, pick_colour, rng_for,
                     save_texture, stroke_colour)

UPRIGHT = math.pi / 2  # blades run roughly vertical on the tile

SPECS = [
    dict(
        id="green",
        ramp=[(0.0, (118, 186, 84)), (0.5, (130, 194, 88)), (1.0, (140, 202, 92))],
        tone=[(16, 0.5), (48, 0.25)],
        speckle=0.02, stripe=0.0,
        strokes=dict(count=60000, length=(3, 6), widths=(1,), jitter=1.2, tone=(0.3, 0.9), stripe=0.0),
        use="Putting surface: finest, smoothest, brightest turf.",
    ),
    dict(
        id="collar",
        ramp=[(0.0, (70, 134, 56)), (0.5, (90, 154, 64)), (1.0, (112, 176, 76))],
        tone=[(8, 0.6), (24, 0.3)],
        speckle=0.04, stripe=0.0,
        # Combed look: 8 px period banding along the blade direction (60 deg).
        # (m, n) = (-55, 32) gives |k| = 63.7 cycles per tile, so it wraps exactly.
        wave=(-55, 32, 0.035),
        strokes=dict(count=90000, length=(4, 7), widths=(1,), jitter=0.2, angle=math.pi / 3,
                     tone=(0.0, 1.0), stripe=0.0),
        use="Collar between green and fairway: short, fine, directional grain, darker than green.",
    ),
    dict(
        id="fairway_light",
        ramp=[(0.0, (64, 134, 60)), (0.5, (92, 156, 68)), (1.0, (118, 178, 80))],
        tone=[(4, 1.0), (12, 0.5), (40, 0.2)],
        speckle=0.04, stripe=0.035, stripe_cycles=4,
        strokes=dict(count=45000, length=(5, 10), widths=(1, 2), jitter=1.0, tone=(0.2, 0.85), stripe=0.035),
        use="Fairway mow stripes, light band (lighter stripe of the mow pattern).",
    ),
    dict(
        id="fairway_dark",
        ramp=[(0.0, (52, 112, 52)), (0.5, (76, 138, 60)), (1.0, (98, 160, 70))],
        tone=[(4, 1.0), (12, 0.5), (40, 0.2)],
        speckle=0.04, stripe=0.045, stripe_cycles=4,
        strokes=dict(count=45000, length=(5, 10), widths=(1, 2), jitter=1.0, tone=(0.2, 0.85), stripe=0.045),
        use="Fairway mow stripes, darker alternate stripe; pair with fairway_light.",
    ),
    dict(
        id="first_cut",
        ramp=[(0.0, (56, 120, 56)), (0.5, (84, 148, 64)), (1.0, (106, 168, 76))],
        tone=[(4, 1.0), (12, 0.7), (36, 0.3)],
        speckle=0.05, stripe=0.02, stripe_cycles=4,
        strokes=dict(count=70000, length=(6, 11), widths=(1,), jitter=0.9, tone=(0.15, 0.85), stripe=0.02),
        use="First cut (fringe between fairway and rough): medium blades.",
    ),
    dict(
        id="second_cut",
        ramp=[(0.0, (44, 98, 46)), (0.5, (64, 122, 52)), (1.0, (86, 144, 60))],
        tone=[(3, 1.0), (10, 0.8), (32, 0.4)],
        speckle=0.06, stripe=0.0,
        strokes=dict(count=55000, length=(9, 16), widths=(2, 3), jitter=1.0, tone=(0.05, 0.95), stripe=0.0),
        use="Second cut (transition to rough): darker, coarser, longer blades than first_cut.",
    ),
    dict(
        id="deep_rough",
        ramp=[(0.0, (30, 74, 42)), (0.5, (48, 100, 54)), (1.0, (72, 122, 60))],
        tone=[(3, 1.0), (8, 0.8), (24, 0.6), (64, 0.3)],
        speckle=0.12, stripe=0.0,
        strokes=dict(count=26000, length=(14, 30), widths=(2, 3), jitter=0.7, tone=(0.0, 1.0), stripe=0.0),
        use="Deep rough: darkest, noisiest, long coarse blades.",
    ),
    dict(
        id="native_fescue",
        ramp=[(0.0, (72, 102, 56)), (0.5, (124, 138, 72)), (1.0, (168, 160, 96))],
        tone=[(4, 1.0), (10, 0.6), (28, 0.4)],
        speckle=0.05, stripe=0.0,
        strokes=dict(count=40000, length=(10, 22), widths=(1,), jitter=0.5, tone=(0.1, 0.95), stripe=0.0),
        flecks=dict(count=3500, length=(2, 4), widths=(1, 2), jitter=0.9,
                    colours=[(201, 143, 74), (214, 186, 120)]),
        use="Native fescue: tall wispy tan-green grass with golden flecks.",
    ),
]


def _render(spec):
    rng = rng_for(spec["id"])
    lut = make_lut(spec["ramp"])
    cycles = spec.get("stripe_cycles", 8)
    tone = fbm(rng, spec["tone"])
    wave = spec.get("wave")
    img = paint(lut, tone, rng=rng, speckle=spec["speckle"], stripe_amp=spec["stripe"],
                stripe_cycles=cycles, wave=wave)
    s = spec["strokes"]
    draw_strokes(img, rng, s["count"], s["length"], s["widths"], s.get("angle", UPRIGHT), s["jitter"],
                 stroke_colour(lut, s["tone"][0], s["tone"][1], stripe_amp=s["stripe"],
                               stripe_cycles=cycles, wave=wave))
    if "flecks" in spec:
        f = spec["flecks"]
        draw_strokes(img, rng, f["count"], f["length"], f["widths"], UPRIGHT, f["jitter"],
                     pick_colour(f["colours"]))
    return img


def build(out_dir):
    entries = []
    for spec in SPECS:
        entries.append(save_texture(out_dir, "turf", spec["id"], _render(spec), spec["use"]))
    return entries
