"""Props family: flagsticks (collision), cup, tee markers and yardage markers (visual only).

Output: assets/models/props/<id>.glb. Ids, part names, pivots, sizes and collision follow the v1 Godot
generator (tools/assets/_legacy_godot/families/props.gd). Yardage plates use the textures written by
tools/assets/make_yardage_plates.py (that script is run here only when a PNG is missing).

Round parts (pole, ferrule, cup, tee) are surfaces of revolution: their bevels are part of the profile,
so the triangle count stays predictable without a modifier. Boxes (post, cap, block, plate) use the kit's
Bevel modifier or plain faces, applied in finish(). The Flag part has its own origin at the pole edge.
"""

import math
import os
import subprocess

import bt_kit as bt

PLATE_DIR = os.path.join(bt.MODELS_DIR, "props", "textures")
PLATE_SCRIPT = os.path.join(bt.PROJECT_ROOT, "tools", "assets", "make_yardage_plates.py")

# ---------------------------------------------------------------- flagstick constants
POLE_RADIUS = 0.0125
POLE_HEIGHT = 2.13
FERRULE_TOP = 0.07
BAND_LOW, BAND_HIGH = 1.74, 1.80
CLOTH_TOP = 2.10
CLOTH_HEIGHT = 0.35
CLOTH_WIDTH = 0.49

# ---------------------------------------------------------------- cup constants
CUP_INNER = 0.054
CUP_OUTER = 0.060
CUP_DEPTH = 0.1016
CUP_FLOOR = 0.006

# ---------------------------------------------------------------- yardage constants
PLATE_HALF_W = 0.18
PLATE_Z_LOW, PLATE_Z_HIGH = 0.57, 0.79
PLATE_Y = 0.06           # centre of the slab: on the post's front face (post half depth 0.06)
PLATE_THICK = 0.02       # slab thickness: front face 0.07 (1 cm proud of the post), back face 0.05

INSET_DARK = bt.ROCK_DARK


# ---------------------------------------------------------------- mesh helpers
def _lathe(part, profile, segments):
    """Adds a surface of revolution around Z. `profile` is a list of (radius, z) points running from the
    axis to the axis: the first and last points have radius 0 and become single apex vertices, which
    closes the surface. Vertices are shared around each ring, so the mesh is watertight."""
    bm = part.bm
    rings = []
    for radius, z in profile:
        if radius <= 1e-9:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((radius * math.cos(2 * math.pi * i / segments),
                                        radius * math.sin(2 * math.pi * i / segments), z))
                          for i in range(segments)])
    new_faces = []
    for k in range(len(rings) - 1):
        a_ring, b_ring = rings[k], rings[k + 1]
        if len(a_ring) == 1 and len(b_ring) == 1:
            continue
        for i in range(segments):
            j = (i + 1) % segments
            if len(a_ring) == 1:
                verts = [a_ring[0], b_ring[j], b_ring[i]]
            elif len(b_ring) == 1:
                verts = [a_ring[i], a_ring[j], b_ring[0]]
            else:
                verts = [a_ring[i], a_ring[j], b_ring[j], b_ring[i]]
            new_faces.append(bm.faces.new(verts))
    bm.normal_update()
    # Make the normals point outward: a closed surface with negative signed volume is inside out.
    if bm.calc_volume(signed=True) < 0.0:
        for face in new_faces:
            face.normal_flip()


def _orient(part, faces, hint):
    """Flips faces so their normals point along `hint` (a Vector); used for the flag sheets."""
    part.bm.normal_update()
    for face in faces:
        if face.normal.dot(hint) < 0.0:
            face.normal_flip()


# ---------------------------------------------------------------- flagsticks
def _pole_rule(flag_swatch):
    """Swatch by height: bronze ferrule at the foot, flag colour on the band, white pole elsewhere."""
    def rule(normal, centre):
        if centre.z < FERRULE_TOP - 0.001:
            return bt.BRONZE
        if BAND_LOW <= centre.z <= BAND_HIGH:
            return flag_swatch
        return bt.WHITE
    return rule


def _cloth_point(u, v, offset):
    """Cloth point in Blender space. u runs across the flag from the pole edge, v down from the top.
    Two sine ripples: one along the width (u) that grows toward the free end, one along the length (v).
    `offset` moves the sheet back along -Y for the reverse side."""
    x = POLE_RADIUS + CLOTH_WIDTH * u
    z = CLOTH_TOP - CLOTH_HEIGHT * v
    ripple_u = 0.045 * math.sin(2 * math.pi * 1.25 * u) * (0.3 + 0.7 * v)
    ripple_v = 0.022 * math.sin(2 * math.pi * 1.0 * v + 1.2) * (0.4 + 0.6 * u)
    return (x, ripple_u + ripple_v - offset, z)


def _flagstick(colour, flag_swatch, out_dir, seed):
    asset = bt.Asset("flagstick_" + colour, "props", seed=seed, ao_distance=0.3)

    pole = asset.part("Pole")
    # Foot to top: bronze bevelled ferrule, white pole with a coloured band 1.74-1.80 m, chamfered top.
    _lathe(pole, [
        (0.0, 0.0), (0.0140, 0.0), (0.0158, 0.0035), (0.0158, 0.0665), (POLE_RADIUS, FERRULE_TOP),
        (POLE_RADIUS, BAND_LOW), (POLE_RADIUS, BAND_HIGH), (POLE_RADIUS, 2.12),
        (0.0118, POLE_HEIGHT), (0.0, POLE_HEIGHT),
    ], segments=12)
    pole.swatch(_pole_rule(flag_swatch))

    # Cloth: a 6 x 4 grid, once facing +Y and once facing -Y, so it reads from both sides.
    # The Flag node origin sits on the pole edge where the cloth attaches (top of the pole, v1 position
    # (0.0125, 2.10, 0) in Godot). The mesh itself stays where _cloth_point puts it.
    flag = asset.part("Flag", origin=(POLE_RADIUS, 0.0, CLOTH_TOP))
    cols, rows = 6, 4
    for offset, hint_y in ((0.0, 1.0), (0.003, -1.0)):
        before = len(flag.bm.faces)
        flag.add_grid(lambda u, v, o=offset: _cloth_point(u, v, o), cols, rows)
        _orient(flag, list(flag.bm.faces)[before:], (0.0, hint_y, 0.0))
    flag.swatch(flag_swatch)

    collision = bt.cylinder_collision(POLE_RADIUS, POLE_HEIGHT)
    return asset.finish(out_dir, collision=collision)


# ---------------------------------------------------------------- cup
def _cup_rule(normal, centre):
    """White rim (with its two small chamfers), dark inside, mid outside, underside mid, floor dark."""
    if centre.z > -0.0035:
        return bt.WHITE
    if normal.z < -0.5:
        return bt.ROCK_MID
    if normal.z > 0.5:
        return INSET_DARK
    if normal.x * centre.x + normal.y * centre.y < 0.0:
        return INSET_DARK
    return bt.ROCK_MID


def _cup(out_dir):
    asset = bt.Asset("cup", "props", seed=11, pivot="rim", ao_distance=0.3)
    liner = asset.part("Liner")
    # Closed solid of revolution: a 6 mm wall, a 6 mm floor and small chamfers on the rim.
    _lathe(liner, [
        (0.0, -CUP_DEPTH + CUP_FLOOR),
        (CUP_INNER, -CUP_DEPTH + CUP_FLOOR),
        (CUP_INNER, -0.004),
        (CUP_INNER + 0.002, 0.0),
        (CUP_OUTER - 0.002, 0.0),
        (CUP_OUTER, -0.002),
        (CUP_OUTER, -CUP_DEPTH),
        (0.0, -CUP_DEPTH),
    ], segments=16)
    liner.swatch(_cup_rule)
    return asset.finish(out_dir)


# ---------------------------------------------------------------- tee markers
TEE_MARKER_VARIATION = {"scale": [0.95, 1.05], "random_yaw": False, "palettes": ["default"]}


def _ball(asset, swatch):
    body = asset.part("Body")
    body.add_icosphere((0.0, 0.0, 0.29), radius=0.29, subdivisions=2)
    # Flatten the underside: the bottom of the sphere is cut to a flat disc, so the ball sits level.
    for v in body.bm.verts:
        if v.co.z < 0.05:
            v.co.z = 0.05
    body.swatch(swatch)


def _block(asset, swatch):
    # Plain bevelled box, one colour. Light comes from AO only (no recessed top panel).
    body = asset.part("Body")
    body.add_box((0.0, 0.0, 0.11), (0.30, 0.22, 0.22))
    body.bevel(width=0.012, segments=2, angle_limit_deg=45.0)
    body.swatch(swatch)


def _tee(asset, swatch):
    body = asset.part("Body")
    # Giant golf tee, 0.44 m tall: tapered peg, collar, bevelled rim of the cupped head.
    _lathe(body, [
        (0.0, 0.0), (0.011, 0.0), (0.0135, 0.008), (0.0165, 0.26), (0.030, 0.31), (0.072, 0.38),
        (0.086, 0.415), (0.088, 0.43), (0.082, 0.44), (0.050, 0.428), (0.020, 0.410), (0.0, 0.400),
    ], segments=12)
    body.swatch(swatch)


def _tee_marker(style, colour_name, swatch, out_dir, seed):
    asset = bt.Asset("tee_marker_%s_%s" % (style, colour_name), "props", seed=seed, ao_distance=0.3)
    if style == "ball":
        _ball(asset, swatch)
    elif style == "block":
        _block(asset, swatch)
    else:
        _tee(asset, swatch)
    return asset.finish(out_dir, variation=dict(TEE_MARKER_VARIATION))


# ---------------------------------------------------------------- yardage markers
def _plate_uv():
    """UV for the plate: the number reads upright from the front (+Y in Blender, -Z in Godot) and from the
    back (-Y in Blender, +Z in Godot). Image left is +X on the front and -X on the back; image top is the top
    of the plate on both sides, so the number is never mirrored."""
    def fn(co, normal):
        v = (co.z - PLATE_Z_LOW) / (PLATE_Z_HIGH - PLATE_Z_LOW)
        if normal.y >= 0.0:
            u = (PLATE_HALF_W - co.x) / (2.0 * PLATE_HALF_W)
        else:
            u = (co.x + PLATE_HALF_W) / (2.0 * PLATE_HALF_W)
        return (u, v)
    return fn


def _plate(asset, texture, cap_swatch):
    # One thin slab (PLATE_THICK) straddling the post's front face, so the plate passes through the post.
    # Front and back faces (normal along Y) carry the number; the four edges take the cap colour.
    plate = asset.part("Plate")
    z0, z1 = PLATE_Z_LOW, PLATE_Z_HIGH
    plate.add_box((0.0, PLATE_Y, (z0 + z1) / 2.0), (2.0 * PLATE_HALF_W, PLATE_THICK, z1 - z0))
    plate.uv_from(_plate_uv())
    plate.set_texture(texture, "Linear", faces=lambda normal: abs(normal.y) > 0.5)
    plate.swatch(cap_swatch)


def _yardage(distance, cap_swatch, out_dir, seed):
    texture = os.path.join(PLATE_DIR, "yardage_%d.png" % distance)
    if not os.path.isfile(texture):
        subprocess.run(["python3", PLATE_SCRIPT], cwd=bt.PROJECT_ROOT, check=True)
    asset = bt.Asset("yardage_marker_%d" % distance, "props", seed=seed, ao_distance=0.5)

    post = asset.part("Post")
    post.add_box((0.0, 0.0, 0.425), (0.12, 0.12, 0.85))
    post.bevel(width=0.008, segments=2, angle_limit_deg=45.0)
    post.swatch(bt.facing(light=bt.TRUNK, mid=bt.TRUNK, dark=bt.TRUNK_DARK))

    cap = asset.part("Cap")
    cap.add_box((0.0, 0.0, 0.875), (0.15, 0.15, 0.05))
    cap.bevel(width=0.008, segments=2, angle_limit_deg=45.0)
    cap.swatch(cap_swatch)

    _plate(asset, texture, cap_swatch)
    return asset.finish(out_dir)


# ---------------------------------------------------------------- entry point
def build(out_dir):
    entries = []
    flags = [("red", bt.FLAG_RED), ("yellow", bt.FLOWER_YELLOW), ("blue", bt.BLUE)]
    for index, (colour, swatch) in enumerate(flags):
        entries.append(_flagstick(colour, swatch, out_dir, seed=index + 1))
    entries.append(_cup(out_dir))

    colours = [("white", bt.WHITE), ("blue", bt.BLUE), ("red", bt.FLAG_RED), ("gold", bt.BRONZE)]
    seed = 100
    for style in ("ball", "block", "tee"):
        for colour_name, swatch in colours:
            seed += 1
            entries.append(_tee_marker(style, colour_name, swatch, out_dir, seed))

    yardages = [(100, bt.FLAG_RED), (150, bt.WHITE), (200, bt.BLUE), (250, bt.BRONZE)]
    for index, (distance, cap_swatch) in enumerate(yardages):
        entries.append(_yardage(distance, cap_swatch, out_dir, seed=300 + index))
    return entries
