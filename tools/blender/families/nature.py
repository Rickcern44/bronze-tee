"""NATURE family: rocks and shrubs (all visual_only). Blender port of the v1 Godot generator.

Keeps the same 12 ids, part names (Body, plus Flowers on flowering shrubs), pivots (large rocks "sunk")
and roughly the same sizes as the v1 nature.gd. Rocks use the darker ROCK swatches by facing; shrubs use
LEAF swatches by facing; grass blades are LEAF_MID at the base and LEAF_LIGHT at the tips.
Deterministic: every random draw comes from bt.rng_for(asset id, salt, seed).

Output: assets/models/nature/<id>.glb. Built only through build.py (--family=nature).
"""

import math

import bt_kit as bt

FAMILY = "nature"
GOLDEN_ANGLE = 2.39996

ROCK_SHADE = bt.facing(bt.ROCK_LIGHT, bt.ROCK_MID, bt.ROCK_DARK)
LEAF_SHADE = bt.facing(bt.LEAF_LIGHT, bt.LEAF_MID, bt.LEAF_DARK)


def _rock_variation():
    return {"scale": [0.8, 1.25], "random_yaw": True, "palettes": ["default"]}


def _shrub_variation():
    return {"scale": [0.85, 1.2], "random_yaw": True, "palettes": ["default", "autumn"]}


def _grass_variation():
    return {"scale": [0.85, 1.2], "random_yaw": True, "palettes": ["default"]}


def _flatten(part, threshold, level):
    """Pulls every vertex below `threshold` up/down to `level`, giving a broad flat underside."""
    for v in part.bm.verts:
        if v.co.z < threshold:
            v.co.z = level


# Rock specs. lobes are (x, y, sx, sy, sz): semi-axes in metres, each lobe stands on the base plane.
# Total height of a rock is 2 * sz of its tallest lobe; large rocks sink `sink` of their height below Z=0.
ROCKS = [
    dict(id="rock_small_a", seed=4101, sink=0.0, subdiv=3, ratio=0.40, bevel=0.010, pivot="base",
         lobes=[(0.0, 0.0, 0.20, 0.20, 0.12)]),
    dict(id="rock_small_b", seed=4102, sink=0.0, subdiv=3, ratio=0.25, bevel=0.010, pivot="base",
         lobes=[(-0.05, 0.0, 0.17, 0.16, 0.085), (0.09, -0.02, 0.13, 0.12, 0.07)]),
    dict(id="rock_medium_a", seed=4201, sink=0.0, subdiv=3, ratio=0.40, bevel=0.018, pivot="base",
         lobes=[(0.0, 0.0, 0.45, 0.45, 0.31)]),
    dict(id="rock_medium_b", seed=4202, sink=0.0, subdiv=3, ratio=0.22, bevel=0.018, pivot="base",
         lobes=[(-0.14, 0.0, 0.36, 0.32, 0.20), (0.22, -0.05, 0.26, 0.24, 0.17)]),
    dict(id="rock_large_a", seed=4301, sink=0.18, subdiv=3, ratio=0.36, bevel=0.030, pivot="sunk",
         lobes=[(0.0, 0.0, 0.90, 0.90, 0.63)]),
    dict(id="rock_large_b", seed=4302, sink=0.18, subdiv=3, ratio=0.30, bevel=0.030, pivot="sunk",
         lobes=[(-0.22, 0.0, 0.66, 0.80, 0.41), (0.44, -0.10, 0.44, 0.60, 0.33)]),
]

# Shrub blobs: (x, y, z_centre, rx, ry, rz) semi-axes in metres. Bottom of each blob sits near Z=0.
SHRUB_ROUND_A = [
    (0.00, 0.00, 0.42, 0.38, 0.40, 0.42),
    (0.27, 0.08, 0.26, 0.26, 0.28, 0.26),
    (-0.27, -0.06, 0.24, 0.24, 0.26, 0.24),
    (0.04, -0.25, 0.20, 0.24, 0.22, 0.20),
]
SHRUB_ROUND_B = [
    (0.00, 0.02, 0.40, 0.36, 0.34, 0.40),
    (-0.26, 0.10, 0.26, 0.28, 0.26, 0.26),
    (0.22, -0.14, 0.22, 0.27, 0.24, 0.22),
]


def _rock(out_dir, spec):
    asset = bt.Asset(spec["id"], FAMILY, seed=spec["seed"], pivot=spec["pivot"], ao_distance=0.3,
                     visual_only=True)
    body = asset.part("Body")
    sink = spec["sink"]
    lobes = spec["lobes"]
    height = max(2.0 * l[4] for l in lobes)
    across = max(2.0 * max(l[2], l[3]) for l in lobes)
    base = -sink * height
    for (x, y, sx, sy, sz) in lobes:
        body.add_icosphere((x, y, base + sz), radius=0.5, subdivisions=spec["subdiv"],
                           scale=(2.0 * sx, 2.0 * sy, 2.0 * sz))
    # chunky irregular form: noise scaled to the rock's size, frequency so facets are ~a third of the width
    body.displace_noise(amplitude=0.10 * across, frequency=2.2 / across, salt="rock")
    # flat base: everything in the bottom band is pulled onto the base plane
    _flatten(body, base + 0.14 * height, base)
    # bevel first so the decimate pass also thins the bevel facets and keeps the count under budget
    body.bevel(width=spec["bevel"], segments=1, angle_limit_deg=30.0)
    body.decimate(spec["ratio"])
    body.swatch(ROCK_SHADE)
    return asset.finish(out_dir, variation=_rock_variation())


def _shrub_body(asset, blobs):
    body = asset.part("Body")
    for (x, y, z, rx, ry, rz) in blobs:
        body.add_icosphere((x, y, z), radius=0.5, subdivisions=2, scale=(2.0 * rx, 2.0 * ry, 2.0 * rz))
    body.displace_noise(amplitude=0.05, frequency=4.0, salt="shrub")
    _flatten(body, 0.10, 0.0)          # flat underside resting on Z=0
    body.swatch(LEAF_SHADE)
    return body


def _flowers(asset, blobs, count, swatch):
    """Adds `count` small five-point stars on the upper half of the blobs (one flat fan each, 10 triangles)."""
    part = asset.part("Flowers")
    part.swatch(swatch)
    rng = bt.rng_for(asset.asset_id, "flowers", asset.seed)
    outer, inner = 0.095, 0.042
    for _ in range(count):
        x, y, z, rx, ry, rz = blobs[rng.randrange(len(blobs))]
        theta = rng.uniform(0.0, 2.0 * math.pi)
        dz = rng.uniform(0.30, 0.95)
        hr = math.sqrt(1.0 - dz * dz)
        d = (math.cos(theta) * hr, math.sin(theta) * hr, dz)
        centre = (x + d[0] * rx, y + d[1] * ry, z + d[2] * rz)
        n = (d[0] / rx, d[1] / ry, d[2] / rz)           # ellipsoid normal at that point
        length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
        normal = bt.Vector(n) / length
        helper = bt.Vector((0.0, 0.0, 1.0)) if abs(normal.z) < 0.9 else bt.Vector((1.0, 0.0, 0.0))
        u = normal.cross(helper).normalized()
        v = normal.cross(u).normalized()
        ring = []
        for k in range(10):
            ang = 2.0 * math.pi * k / 10.0
            r = outer if k % 2 == 0 else inner
            p = (bt.Vector(centre) + normal * 0.012 + (u * math.cos(ang) + v * math.sin(ang)) * r)
            ring.append((p.x, p.y, p.z))
        part.add_poly(ring)


def _shrub_round(out_dir, asset_id, seed, blobs):
    asset = bt.Asset(asset_id, FAMILY, seed=seed, ao_distance=0.4, visual_only=True)
    _shrub_body(asset, blobs)
    return asset.finish(out_dir, variation=_shrub_variation())


def _shrub_flowering(out_dir, asset_id, seed, blobs, swatch):
    asset = bt.Asset(asset_id, FAMILY, seed=seed, ao_distance=0.4, visual_only=True)
    _shrub_body(asset, blobs)
    _flowers(asset, blobs, 16, swatch)
    return asset.finish(out_dir, variation=_shrub_variation())


def _grass(out_dir, asset_id, seed, count, height, lean_lo, lean_hi, width):
    """Tapered blades that bend outward. Each blade: two quads (LEAF_MID base) and a tip triangle (LEAF_LIGHT)."""
    asset = bt.Asset(asset_id, FAMILY, seed=seed, ao_distance=0.4, visual_only=True)
    body = asset.part("Body")
    body.swatch(lambda normal, centre: bt.LEAF_LIGHT if centre.z > 0.45 * height else bt.LEAF_MID)
    rng = bt.rng_for(asset_id, "blades", seed)
    up = bt.Vector((0.0, 0.0, 1.0))
    for i in range(count):
        theta = i * GOLDEN_ANGLE + rng.uniform(-0.2, 0.2)
        out = bt.Vector((math.cos(theta), math.sin(theta), 0.0))
        side = bt.Vector((-math.sin(theta), math.cos(theta), 0.0))
        h = height * rng.uniform(0.7, 1.0)
        lean = rng.uniform(lean_lo, lean_hi)
        base = out * rng.uniform(0.0, 0.06)
        w0 = width * rng.uniform(0.9, 1.1)
        w1 = w0 * 0.55

        def centre_at(t):
            return base + up * (h * t) + out * (h * lean * t * t)

        p0, p1, p2 = centre_at(0.0), centre_at(0.5), centre_at(1.0)
        l0, r0 = p0 - side * (w0 / 2.0), p0 + side * (w0 / 2.0)
        l1, r1 = p1 - side * (w1 / 2.0), p1 + side * (w1 / 2.0)
        body.add_tri(tuple(l0), tuple(r0), tuple(r1))
        body.add_tri(tuple(l0), tuple(r1), tuple(l1))
        # tip: add_blade gives the upper triangle from the mid-blade width to the tip, bent a little further out
        body.add_blade(tuple(p1), tuple(p2), w1, bend=tuple(out * (h * 0.04)))
    return asset.finish(out_dir, variation=_grass_variation())


def build(out_dir):
    out = []
    for spec in ROCKS:
        out.append(_rock(out_dir, spec))
    out.append(_shrub_round(out_dir, "shrub_round_a", 5101, SHRUB_ROUND_A))
    out.append(_shrub_round(out_dir, "shrub_round_b", 5201, SHRUB_ROUND_B))
    out.append(_shrub_flowering(out_dir, "shrub_flowering_a", 5301, SHRUB_ROUND_A, bt.FLOWER_PINK))
    out.append(_shrub_flowering(out_dir, "shrub_flowering_b", 5401, SHRUB_ROUND_B, bt.FLOWER_YELLOW))
    out.append(_grass(out_dir, "shrub_grass_a", 5501, 20, 0.80, 0.25, 0.60, 0.10))
    out.append(_grass(out_dir, "shrub_grass_b", 5601, 24, 0.95, 0.05, 0.25, 0.09))
    return out
