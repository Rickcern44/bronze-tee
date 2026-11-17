"""Bronze Tee tree family (Blender 5.3, headless): 16 low-poly trees for assets/models/trees/.

Ids, part names (Trunk, Canopy), variation and rough heights match the v1 Godot generator
(tools/assets/_legacy_godot/families/trees.gd). Build with:
    build.py --family=trees

Shapes
- broadleaf a/b/c (medium, large): a tapered trunk with 2-3 forked branches that end inside the crown, and a
  crown of 4-7 displaced icospheres (one bridge blob over the trunk, a few lumps, a top blob). Seeds set the
  lean, crown spread and squash (a round, b wide and flat, c tall and oval).
- pine a/b/c (medium, tall): a visible tapered trunk, 6 (medium) or 8 (tall) overlapping closed star-shaped
  drooping tiers (6-9 jagged tips, alternating phase, jitter per seed). Tips reach past the tier below, so the
  skirts overlap and hide the trunk. Each tier has an undercut layer, and a small cone sits on top.
- poplar a/b: slim trunk, tall narrow column of stacked ellipsoids.
- ornamental a/b (small, about 5 m): short curving trunk (two segments) under a round or wide crown.

Everything is built in Blender space (Z up, front +Y) with bmesh, then the shared kit does swatches, flat
shading, the AO bake, export and the manifest entry. The lean is one rotation matrix applied to every
created vertex, so trunk, forks and crown stay attached.
"""

import math

import bmesh
from mathutils import Matrix, Vector

import bt_kit as bt

FAMILY = "trees"
AO_DISTANCE = 1.5
TREE_VARIATION = {"scale": [0.85, 1.15], "random_yaw": True, "palettes": ["default", "autumn"]}
PINE_VARIATION = {"scale": [0.85, 1.15], "random_yaw": True, "palettes": ["default"]}

BROADLEAF = {
    "a": {"seed": 1100, "lean": 2.5, "lean_dir": 0.4, "forks": 2, "squash": 1.0, "spread": 0.95,
          "taper": 0.6, "top": {"medium": 7.5, "large": 14.4}, "base": {"medium": 3.4, "large": 5.6}},
    "b": {"seed": 1200, "lean": -3.0, "lean_dir": 2.1, "forks": 3, "squash": 0.7, "spread": 1.25,
          "taper": 0.8, "top": {"medium": 8.5, "large": 11.9}, "base": {"medium": 3.0, "large": 4.6}},
    "c": {"seed": 1300, "lean": 4.5, "lean_dir": 4.0, "forks": 2, "squash": 1.25, "spread": 0.7,
          "taper": 0.55, "top": {"medium": 8.8, "large": 13.4}, "base": {"medium": 3.2, "large": 5.0}},
}
BROADLEAF_SIZE = {
    "medium": {"radius": 2.0, "lumps": (2, 3), "trunk_r": 0.40, "crowns": 2},
    "large": {"radius": 2.7, "lumps": (4, 5), "trunk_r": 0.55, "crowns": 3},
}

PINE = {
    "a": {"seed": 2100, "lean": 1.5, "lean_dir": 0.9, "tiers": {"medium": 6, "tall": 8},
          "top": {"medium": 11.3, "tall": 17.5}, "width": {"medium": 3.18, "tall": 2.85}},
    "b": {"seed": 2200, "lean": -2.0, "lean_dir": 3.0, "tiers": {"medium": 6, "tall": 8},
          "top": {"medium": 11.0, "tall": 18.2}, "width": {"medium": 2.87, "tall": 2.63}},
    "c": {"seed": 2300, "lean": 2.5, "lean_dir": 5.0, "tiers": {"medium": 6, "tall": 8},
          "top": {"medium": 11.3, "tall": 17.5}, "width": {"medium": 3.12, "tall": 2.82}},
}
# Lowest tier valley (tips must stay above the ground), and the tier count per size.
PINE_FIRST = {"medium": 2.6, "tall": 2.9}
PINE_SIZE_CROWNS = {"medium": 2, "tall": 3}
PINE_POINTS = {"medium": (7, 9), "tall": (6, 8)}   # tiers x 2 skirts x 8P tris: tall worst case ~1090
PINE_DROP = 1.3          # tips hang 1.3 tier spacings below their valley: they reach over the tier below
PINE_TOP_RATIO = 0.65    # the top tier is 65% of the bottom width (gentle taper, fuller middle)

UP = Vector((0.0, 0.0, 1.0))
PINE_CONE_LENGTH = 2.2


# ---------------------------------------------------------------- bmesh primitives (Blender space)

def _lean_matrix(lean_deg, lean_dir_rad):
    """Tilts the whole tree about its base. Applied to every created vertex, so parts stay attached."""
    axis = Vector((math.cos(lean_dir_rad), math.sin(lean_dir_rad), 0.0))
    return Matrix.Rotation(math.radians(lean_deg), 4, axis)


def _limb(part, lean, base, direction, length, r_base, r_tip, segs):
    """A (possibly tapered) cylinder from `base` along `direction` for `length`, capped. Cone when r_tip is 0."""
    d = Vector(direction).normalized()
    rot = UP.rotation_difference(d).to_matrix().to_4x4()
    centre = Vector(base) + d * (length / 2.0)
    bmesh.ops.create_cone(part.bm, cap_ends=True, cap_tris=False, segments=int(segs),
                          radius1=float(r_base), radius2=float(r_tip), depth=float(length),
                          matrix=lean @ (Matrix.Translation(centre) @ rot))


def _blob(part, lean, centre, radii, subdiv):
    """An icosphere with semi-axes `radii` (rx, ry, rz) at `centre`. Displaced later by the canopy."""
    rx, ry, rz = radii
    matrix = lean @ Matrix.Translation(Vector(centre)) @ Matrix.Diagonal((rx, ry, rz, 1.0))
    bmesh.ops.create_icosphere(part.bm, subdivisions=int(subdiv), radius=1.0, matrix=matrix)


def _star_tier(part, lean, z, outer, inner, points, drop, thick, phase, rng):
    """A closed jagged skirt: a star-shaped top (tips at z - drop, valleys at z) and a flat underside `thick`
    lower, joined by a side strip so there are no holes. Fans from the centres, outward winding."""
    ring = []
    for k in range(points * 2):
        ang = phase + math.pi * k / points
        if k % 2 == 0:
            r = outer * (1.0 + rng.uniform(-0.07, 0.07))
            dz = -drop * (1.0 + rng.uniform(-0.12, 0.12))
        else:
            r = inner * (1.0 + rng.uniform(-0.05, 0.05))
            dz = 0.0
        ring.append((r * math.cos(ang), r * math.sin(ang), z + dz))
    n = len(ring)
    mean_x = sum(p[0] for p in ring) / n
    mean_y = sum(p[1] for p in ring) / n
    mean_z = sum(p[2] for p in ring) / n
    bm = part.bm
    top = [bm.verts.new(lean @ Vector(p)) for p in ring]
    bot = [bm.verts.new(lean @ Vector((p[0], p[1], p[2] - thick))) for p in ring]
    c_top = bm.verts.new(lean @ Vector((mean_x, mean_y, mean_z)))
    c_bot = bm.verts.new(lean @ Vector((mean_x, mean_y, mean_z - thick)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((c_top, top[i], top[j]))
        bm.faces.new((c_bot, bot[j], bot[i]))
        bm.faces.new((top[i], bot[j], top[j]))
        bm.faces.new((top[i], bot[i], bot[j]))


def _tidy(part):
    """Makes every face point outward (island by island) before the kit applies modifiers and swatches."""
    bmesh.ops.recalc_face_normals(part.bm, faces=part.bm.faces[:])


def _trunk_part(asset, lean, height, r_bot, r_top, segs, bevel_width=None):
    trunk = asset.part("Trunk")
    _limb(trunk, lean, (0.0, 0.0, 0.0), UP, height, r_bot, r_top, segs)
    trunk.swatch(bt.facing(light=bt.TRUNK, mid=bt.TRUNK, dark=bt.TRUNK_DARK))
    if bevel_width:
        trunk.bevel(width=bevel_width, segments=1)
    return trunk


def _leaf_canopy(asset):
    canopy = asset.part("Canopy")
    canopy.swatch(bt.facing(light=bt.LEAF_LIGHT, mid=bt.LEAF_MID, dark=bt.LEAF_DARK))
    return canopy


def _finish(asset, out_dir, crowns, variation):
    return asset.finish(out_dir, collision=bt.tree_collision(trunk="Trunk", canopy=["Canopy"], crowns=crowns),
                        variation=variation)


# ---------------------------------------------------------------- broadleaf

def _broadleaf(v, size, out_dir):
    cfg = BROADLEAF[v]
    sz = BROADLEAF_SIZE[size]
    asset_id = "tree_broadleaf_%s_%s" % (v, size)
    seed = int(cfg["seed"]) + (0 if size == "medium" else 50)
    rng = bt.rng_for(asset_id, "shape", seed)
    asset = bt.Asset(asset_id, FAMILY, seed=seed, ao_distance=AO_DISTANCE)

    radius = sz["radius"] * rng.uniform(0.96, 1.04)
    squash = cfg["squash"]
    top = cfg["top"][size]
    base = cfg["base"][size]
    lean = _lean_matrix(cfg["lean"], cfg["lean_dir"])
    spread = cfg["spread"] * radius

    # Crown layout (local, before the lean): bridge blob over the trunk top, lumps around it, top blob.
    bridge_y = base + 0.7 * radius * squash
    trunk_h = bridge_y
    n_lumps = rng.randint(*sz["lumps"])
    lumps = []
    phase = rng.uniform(0.0, math.tau)
    for i in range(n_lumps):
        ang = phase + math.tau * i / n_lumps + rng.uniform(-0.35, 0.35)
        dist = spread * rng.uniform(0.45, 1.0)
        y = rng.uniform(base + radius * squash * 0.9, top - radius * squash * 1.8)
        r = radius * rng.uniform(0.82, 1.05)
        lumps.append(((math.cos(ang) * dist, math.sin(ang) * dist, y), r))
    crown_r = radius * 0.9
    crown_c = (rng.uniform(-0.15, 0.15) * radius, rng.uniform(-0.15, 0.15) * radius,
               top - crown_r * squash)

    # Trunk: tapered, bevelled slightly, with forks that end inside lumps.
    r_bot = sz["trunk_r"] * rng.uniform(0.92, 1.08)
    r_top = r_bot * cfg["taper"]
    trunk = _trunk_part(asset, lean, trunk_h, r_bot, r_top, 8, bevel_width=r_bot * 0.12)
    chosen = rng.sample(range(n_lumps), min(cfg["forks"], n_lumps))
    for idx in chosen:
        lc, lr = lumps[idx]
        fork_base = Vector((0.0, 0.0, trunk_h * rng.uniform(0.45, 0.75)))
        target = Vector(lc)
        tip = target + (fork_base - target).normalized() * (0.3 * lr)
        d = tip - fork_base
        _limb(trunk, lean, fork_base, d.normalized(), d.length, r_bot * 0.42, r_bot * 0.2, 6)

    # Crown: lumps are displaced once (noise), the top blob is subdivided one step more for a rounder top.
    canopy = _leaf_canopy(asset)
    _blob(canopy, lean, (0.0, 0.0, bridge_y), (radius * 0.8, radius * 0.8, radius * 0.8 * squash), 2)
    for centre, r in lumps:
        _blob(canopy, lean, centre, (r, r, r * squash), 2)
    _blob(canopy, lean, crown_c, (crown_r, crown_r, crown_r * squash), 3)
    canopy.displace_noise(amplitude=radius * 0.18, frequency=0.9)

    _tidy(trunk)
    _tidy(canopy)
    return _finish(asset, out_dir, sz["crowns"], TREE_VARIATION)


# ---------------------------------------------------------------- pine

def _pine(v, size, out_dir):
    cfg = PINE[v]
    asset_id = "tree_pine_%s_%s" % (v, size)
    seed = int(cfg["seed"]) + (0 if size == "medium" else 40)
    rng = bt.rng_for(asset_id, "shape", seed)
    asset = bt.Asset(asset_id, FAMILY, seed=seed, ao_distance=AO_DISTANCE)

    top = cfg["top"][size]
    width = cfg["width"][size]
    n_tiers = cfg["tiers"][size]
    # The footprint (bounding box) and height match the pre-rework pines within a few percent, so the manifest
    # size is unchanged. Widths were tuned per asset for that: the point count changed, so the tip reach did too.
    lean = _lean_matrix(cfg["lean"], cfg["lean_dir"])

    last = top - PINE_CONE_LENGTH     # valley height of the top tier, the cone starts here
    first = PINE_FIRST[size]          # valley height of the lowest tier
    spacing = (last - first) / float(n_tiers - 1)
    trunk_h = last - 0.4              # trunk top hides inside the tier stack
    trunk = _trunk_part(asset, lean, trunk_h, 0.2, 0.1, 6)

    canopy = _leaf_canopy(asset)
    canopy.swatch(bt.facing(light=bt.PINE, mid=bt.PINE, dark=bt.PINE_DARK))
    lo_pts, hi_pts = PINE_POINTS[size]
    for i in range(n_tiers):
        t = i / float(n_tiers - 1)
        # Wide at the bottom, tapering gently: the top tier keeps PINE_TOP_RATIO of the bottom width.
        outer = width * (1.0 - (1.0 - PINE_TOP_RATIO) * t) * rng.uniform(0.97, 1.03)
        # Valleys well inside the tips: each skirt is a sloping, solid cone of branches, not a thin shard.
        inner = outer * rng.uniform(0.45, 0.55)
        points = rng.randint(lo_pts, hi_pts)
        phase = (i % 2) * math.pi / points + rng.uniform(-0.15, 0.15)
        z = first + spacing * i
        # Tips reach down past the valley of the tier below, so the skirts overlap and hide the trunk.
        drop = PINE_DROP * spacing * rng.uniform(0.95, 1.05)
        _star_tier(canopy, lean, z, outer, inner, points, drop, 0.25, phase, rng)
        # Undercut layer: a smaller skirt half a spacing below, offset in phase, fills the gaps between tiers.
        _star_tier(canopy, lean, z - 0.5 * spacing, outer * 0.6, inner * 0.6, points, drop * 0.6, 0.16,
                   phase + math.pi / points, rng)
    _limb(canopy, lean, (0.0, 0.0, top - PINE_CONE_LENGTH), UP, PINE_CONE_LENGTH, 0.8, 0.0, 12)

    _tidy(trunk)
    _tidy(canopy)
    return _finish(asset, out_dir, PINE_SIZE_CROWNS[size], PINE_VARIATION)


# ---------------------------------------------------------------- poplar

def _poplar(v, out_dir):
    asset_id = "tree_poplar_%s" % v
    seed = 3100 if v == "a" else 3200
    rng = bt.rng_for(asset_id, "shape", seed)
    asset = bt.Asset(asset_id, FAMILY, seed=seed, ao_distance=AO_DISTANCE)
    lean = _lean_matrix(1.0 if v == "a" else -1.5, (1.2 if v == "a" else 4.6))

    if v == "a":
        trunk_h = 3.4
        trunk = _trunk_part(asset, lean, trunk_h, 0.24, 0.15, 6)
        canopy = _leaf_canopy(asset)
        # Four stacked ellipsoids, a thick column with a little wobble per blob.
        ys = [3.7, 5.35, 7.0, 8.65, 10.3]
        for y in ys:
            off = (rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25))
            _blob(canopy, lean, (off[0], off[1], y), (1.75, 1.75, 1.95), 2)
        canopy.displace_noise(amplitude=0.3, frequency=0.9)
        crowns = 2
    else:
        trunk_h = 3.0
        trunk = _trunk_part(asset, lean, trunk_h, 0.22, 0.14, 6)
        canopy = _leaf_canopy(asset)
        # Narrower and taller: two detailed ellipsoids and a smaller one at the bottom.
        _blob(canopy, lean, (0.0, 0.0, 4.2), (1.3, 1.3, 2.3), 2)
        _blob(canopy, lean, (0.0, 0.0, 6.8), (1.3, 1.3, 2.3), 3)
        _blob(canopy, lean, (0.0, 0.0, 9.3), (1.3, 1.3, 2.3), 3)
        canopy.displace_noise(amplitude=0.28, frequency=1.0)
        crowns = 2

    _tidy(trunk)
    _tidy(canopy)
    return _finish(asset, out_dir, crowns, TREE_VARIATION)


# ---------------------------------------------------------------- ornamental

def _ornamental(v, out_dir):
    asset_id = "tree_ornamental_%s_small" % v
    seed = 5100 if v == "a" else 5200
    asset = bt.Asset(asset_id, FAMILY, seed=seed, ao_distance=AO_DISTANCE)
    lean = _lean_matrix(3.0 if v == "a" else -2.0, (2.4 if v == "a" else 0.6))

    # Short curving trunk: a vertical stub, then a second segment bent 20 degrees.
    trunk = asset.part("Trunk")
    trunk.swatch(bt.facing(light=bt.TRUNK, mid=bt.TRUNK, dark=bt.TRUNK_DARK))
    _limb(trunk, lean, (0.0, 0.0, 0.0), UP, 1.0, 0.16, 0.12, 6)
    bend = Vector((math.sin(math.radians(20.0)), 0.0, math.cos(math.radians(20.0))))
    if v == "b":
        bend = Vector((0.0, -math.sin(math.radians(20.0)), math.cos(math.radians(20.0))))
    upper_base = Vector((0.0, 0.0, 1.0))
    _limb(trunk, lean, upper_base, bend, 1.3, 0.12, 0.09, 6)
    top_pt = upper_base + bend * 1.3

    canopy = _leaf_canopy(asset)
    if v == "a":
        # Round crown: one main blob, two satellite lumps.
        _blob(canopy, lean, (top_pt.x, top_pt.y, 3.1), (1.8, 1.8, 1.8), 3)
        _blob(canopy, lean, (1.2, 0.5, 2.8), (0.95, 0.95, 0.95), 2)
        _blob(canopy, lean, (-0.9, -0.3, 3.9), (0.9, 0.9, 0.9), 2)
    else:
        # Wide flattened crown with two lower satellites.
        _blob(canopy, lean, (top_pt.x, top_pt.y, 3.2), (1.9, 1.9, 1.45), 3)
        _blob(canopy, lean, (1.2, 0.2, 2.9), (0.9, 0.9, 0.9), 2)
        _blob(canopy, lean, (-1.0, 0.6, 3.0), (0.9, 0.9, 0.9), 2)
    canopy.displace_noise(amplitude=0.25, frequency=1.0)

    _tidy(trunk)
    _tidy(canopy)
    return _finish(asset, out_dir, 2, TREE_VARIATION)


# ---------------------------------------------------------------- entry point

def build(out_dir):
    out = []
    for size in ("medium", "large"):
        for v in ("a", "b", "c"):
            out.append(_broadleaf(v, size, out_dir))
    for size in ("medium", "tall"):
        for v in ("a", "b", "c"):
            out.append(_pine(v, size, out_dir))
    for v in ("a", "b"):
        out.append(_poplar(v, out_dir))
    for v in ("a", "b"):
        out.append(_ornamental(v, out_dir))
    return out
