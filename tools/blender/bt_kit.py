"""Bronze Tee asset kit (Blender 5.3, headless). Shared core for every asset family.

Usage example (a family module such as families/trees.py), a two-part tree:

    import bt_kit as bt

    def build(out_dir):
        # One Asset per model. Id, family, seed. ao_distance ~1.5 m suits trees (props ~0.3 m).
        asset = bt.Asset("zz_smoke_tree", "zz_smoke", seed=7, ao_distance=1.5)

        # Part 1: the trunk. Geometry is in Blender space: Z up, the front of the model is +Y.
        trunk = asset.part("Trunk")
        trunk.add_cylinder((0, 0, 0), radius_bottom=0.30, radius_top=0.22, depth=5.0, segments=8)
        # Facing swatches: up-facing faces get the first colour, down-facing the third, sides the middle.
        trunk.swatch(bt.facing(light=bt.TRUNK, mid=bt.TRUNK, dark=bt.TRUNK_DARK))
        trunk.bevel(width=0.04, segments=1)     # bevel applied at finish(), counted after modifiers

        # Part 2: the canopy, a displaced icosphere sitting on top of the trunk.
        canopy = asset.part("Canopy")
        canopy.add_icosphere((0, 0, 7.0), radius=2.6, subdivisions=2)
        canopy.displace_noise(amplitude=0.7, frequency=0.6)   # deterministic value noise, seeded
        canopy.swatch(bt.facing(light=bt.LEAF_LIGHT, mid=bt.LEAF_MID, dark=bt.LEAF_DARK))

        # finish() does the rest: applies modifiers, aligns the base pivot to Z=0, triangulates,
        # sets swatch UVs and flat shading, bakes AO into COLOR_0 (remapped 0.55-1.0) against a
        # temporary ground plane, builds the shared palette material, exports the .glb (selected
        # objects only, +Y up, vertex colours on) and returns the manifest entry.
        entry = asset.finish(
            out_dir,
            # tree collision: trunk cylinder up to where the canopy starts, 2 crown spheres fitted
            # to the canopy vertices (Godot space). Other kinds: cylinder_collision, sphere_collision.
            collision=bt.tree_collision(trunk="Trunk", canopy=["Canopy"], crowns=2),
            variation={"scale": [0.85, 1.15], "random_yaw": True,
                       "palettes": ["default", "autumn"]},
        )
        return [entry]

Run it through build.py (see tools/blender/README.md), never directly.

Conventions
- Blender space is Z up. Godot space is Y up and the model faces -Z. The glTF exporter maps
  Blender (x, y, z) to Godot (x, z, -y), so the FRONT of an asset is Blender +Y. to_godot() does the mapping.
- Every asset gets: palette-swatch UVs (facing rule), flat shading (no smooth normals), a Cycles AO bake
  into the COLOR_0 vertex colours remapped to [0.55, 1.0], a temporary ground plane for contact shadow
  (never exported), one shared material, and export of the root empty plus its children as a .glb.
- Determinism: every random draw comes from random.Random derived from (asset id, salt, seed).
  Never use the global random module. Same seed, same file.
- Pivots: "base" (min Z moved to 0), "rim" (max Z moved to 0), "sunk" (no move, must span Z=0).

Public API (all helpers are documented in their docstrings)
- Constants: palette indices TRUNK, TRUNK_DARK, LEAF_LIGHT, LEAF_MID, LEAF_DARK, PINE, PINE_DARK,
  ROCK_LIGHT, ROCK_MID, ROCK_DARK, WHITE, FLAG_RED, BRONZE, BLUE, FLOWER_PINK, FLOWER_YELLOW.
- swatch_uv(index), palette_colours(name), write_palettes(dir), to_godot(v), to_res(path), rng_for(...)
- facing(light, mid, dark, up=0.5, down=-0.5) -> swatch rule for Part.swatch()
- value_noise(x, y, z, seed) -> float in [-1, 1]
- Part: add_cylinder, add_cone, add_box, add_icosphere, add_grid, add_star_tier, add_blade, add_poly,
  displace_noise, transform, bevel, decimate, swatch, uv_from, set_texture
- Asset(asset_id, family, seed, pivot, ao_distance, visual_only): part(name, origin=None), finish(out_dir, ...)
  origin: optional object origin (Blender space) for a part, mesh stays in place (flag cloth at the pole edge).
- tree_collision(trunk, canopy, crowns), cylinder_collision(radius, height), sphere_collision(center, radius)
- planar_uv(...) for textured parts such as yardage plates
- reset_scene() clears the file before a build
"""

import math
import os
import random
import struct
import zlib

import bmesh
import bpy
from mathutils import Matrix, Vector

# ---------------------------------------------------------------- paths
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "models")
PALETTE_DIR = os.path.join(MODELS_DIR, "palette")
PALETTE_FILES = {"default": "palette_default.png", "autumn": "palette_autumn.png"}

# ---------------------------------------------------------------- palette
# Swatch indices, index = row * 4 + col, row 0 at the top of the 64x64 PNG.
TRUNK, TRUNK_DARK = 0, 1
LEAF_LIGHT, LEAF_MID, LEAF_DARK = 2, 3, 4
PINE, PINE_DARK = 5, 6
ROCK_LIGHT, ROCK_MID, ROCK_DARK = 7, 8, 9
WHITE, FLAG_RED, BRONZE, BLUE = 10, 11, 12, 13
FLOWER_PINK, FLOWER_YELLOW = 14, 15

_PALETTE_DEFAULT_HEX = [
    "6B4A32", "4A3224", "8FCB5E", "4F9D45", "2F6B3A", "2F6F4A", "1C4A36", "B3AC9E",
    "8A8478", "5F5A52", "F4F1E6", "E8452C", "C98F4A", "3A78C8", "F28AB8", "FFD15C",
]
_PALETTE_AUTUMN_OVERRIDES = {2: "F2B24A", 3: "DE6B2A", 4: "A63C26"}


def palette_colours(name):
    """Returns the 16 swatches of palette `name` ("default" or "autumn") as (r, g, b) ints."""
    hexes = list(_PALETTE_DEFAULT_HEX)
    if name == "autumn":
        for index, value in _PALETTE_AUTUMN_OVERRIDES.items():
            hexes[index] = value
    elif name != "default":
        raise ValueError("unknown palette: %s" % name)
    return [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in hexes]


def swatch_uv(index):
    """Blender UV (u, v) at the centre of swatch `index`. Matches glTF (u, 1 - v) = ((col+.5)/4, (row+.5)/4)."""
    row, col = divmod(int(index), 4)
    return ((col + 0.5) / 4.0, 1.0 - (row + 0.5) / 4.0)


def _write_png_rgb(path, width, height, rows):
    """Writes an 8-bit RGB PNG. `rows` is a list of bytes objects, one per image row, top row first."""
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + row for row in rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def write_palettes(directory=PALETTE_DIR):
    """Writes palette_default.png and palette_autumn.png (64x64, 4x4 swatches of 16 px) with pure Python.

    Returns {name: absolute path}. Uses no Blender image API, so it works without a display.
    """
    os.makedirs(directory, exist_ok=True)
    paths = {}
    for name, filename in PALETTE_FILES.items():
        colours = palette_colours(name)
        rows = []
        for y in range(64):
            swatch_row = y // 16
            row = bytearray()
            for x in range(64):
                r, g, b = colours[swatch_row * 4 + x // 16]
                row += bytes((r, g, b))
            rows.append(bytes(row))
        path = os.path.join(directory, filename)
        _write_png_rgb(path, 64, 64, rows)
        paths[name] = path
    return paths


def to_res(path):
    """Converts an absolute path under the project into a Godot res:// path."""
    rel = os.path.relpath(os.path.abspath(path), PROJECT_ROOT).replace(os.sep, "/")
    return "res://" + rel


def to_godot(v):
    """Blender (x, y, z) -> Godot (x, z, -y), the same mapping the glTF exporter applies with export_yup."""
    return (float(v[0]), float(v[2]), -float(v[1]))


def rng_for(asset_id, salt="", seed=0):
    """A random.Random seeded from (asset id, salt, seed). Use one per random draw group; never the global RNG."""
    return random.Random(zlib.crc32(("%s|%s|%d" % (asset_id, salt, int(seed))).encode("utf-8")))


def value_noise(x, y, z, seed):
    """Smooth deterministic 3D value noise in [-1, 1]. The same inputs always give the same result."""
    def lattice(ix, iy, iz):
        h = (ix * 374761393 + iy * 668265263 + iz * 1442695041 + int(seed) * 2654435761) & 0xFFFFFFFF
        h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
        h ^= h >> 16
        return h / 0xFFFFFFFF * 2.0 - 1.0

    x0, y0, z0 = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - x0, y - y0, z - z0
    sx, sy, sz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    c = []
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                c.append(lattice(x0 + dx, y0 + dy, z0 + dz))
    x00 = c[0] + (c[1] - c[0]) * sx
    x10 = c[2] + (c[3] - c[2]) * sx
    x01 = c[4] + (c[5] - c[4]) * sx
    x11 = c[6] + (c[7] - c[6]) * sx
    y0v = x00 + (x10 - x00) * sy
    y1v = x01 + (x11 - x01) * sy
    return y0v + (y1v - y0v) * sz


def facing(light, mid, dark, up=0.5, down=-0.5):
    """Swatch rule: faces whose normal points up (Blender +Z) get `light`, down gets `dark`, the rest `mid`.

    Pass the same index for two of them when you want a single colour on those facings.
    """
    def rule(normal, centre):
        if normal.z > up:
            return light
        if normal.z < down:
            return dark
        return mid
    return rule


def planar_uv(origin, width, height):
    """UV function for textured parts: maps X (width) and Z (height) of a face onto the full 0..1 image.

    Use with Part.uv_from(). `origin` is the Blender (x, z) of the image's bottom-left corner.
    Blender UV space has v = 0 at the bottom and v = 1 at the top of the image, so the top of the
    plate (high z) maps to v = 1 and the image reads upright.
    """
    ox, oz = origin

    def fn(co, normal):
        return ((co.x - ox) / width, (co.z - oz) / height)
    return fn


# ---------------------------------------------------------------- scene
def reset_scene():
    """Deletes every object, mesh, material and image left in the file. Called once per build."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras,
                       bpy.data.lights):
        for block in list(collection):
            if block.users == 0:
                collection.remove(block)


def _setup_render(ao_distance, samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = int(samples)
    scene.cycles.use_denoising = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("BronzeTeeWorld")
    scene.world.light_settings.distance = float(ao_distance)
    return scene


def _link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _make_ground(z):
    """A large plane used only as an occluder for the AO bake. It is deleted before export."""
    size = 40.0
    mesh = bpy.data.meshes.new("__ao_ground_mesh")
    mesh.from_pydata([(-size, -size, z), (size, -size, z), (size, size, z), (-size, size, z)], [],
                     [(0, 1, 2, 3)])
    mesh.update()
    return _link(bpy.data.objects.new("__ao_ground", mesh))


def _image(path, interpolation):
    if not os.path.isfile(path):
        raise FileNotFoundError("texture missing: %s (run write_palettes first)" % path)
    image = bpy.data.images.load(path, check_existing=True)
    image.colorspace_settings.name = "sRGB"
    return image


def _make_material(name, image_path, interpolation="Closest"):
    old = bpy.data.materials.get(name)
    if old is not None:
        bpy.data.materials.remove(old)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = _image(image_path, interpolation)
    tex.interpolation = interpolation
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# ---------------------------------------------------------------- parts
class Part:
    """One named mesh object of an asset (for example "Trunk" or "Canopy").

    Geometry is added in Blender space with bmesh. Swatch colours and UVs are assigned at finish() time,
    after modifiers, so bevels and decimation never leave a face with the wrong colour.
    """

    def __init__(self, asset, name):
        self.asset = asset
        self.name = name
        self.bm = bmesh.new()
        self.bm.loops.layers.uv.verify()
        self._rule = facing(LEAF_LIGHT, LEAF_MID, LEAF_DARK)
        self._uv_fn = None
        self._texture = None
        self._texture_interp = "Closest"
        self._texture_faces = None
        self._origin = None
        self._modifiers = []

    # -- swatches and textures
    def swatch(self, rule):
        """Sets how faces pick their palette swatch. `rule` is an int (one swatch for the whole part),
        a function from facing() (chooses by normal), or any callable(normal, centre) -> swatch index."""
        if isinstance(rule, int):
            index = rule
            self._rule = lambda normal, centre: index
        else:
            self._rule = rule
        return self

    def uv_from(self, fn):
        """Replaces swatch UVs with fn(co, normal) -> (u, v). Used for textured parts (yardage plates)."""
        self._uv_fn = fn
        return self

    def set_texture(self, path, interpolation="Linear", faces=None):
        """Gives this part its own image instead of the shared palette (e.g. a yardage plate texture).
        Such a part gets its own material. Pair it with uv_from(...).

        faces: optional callable(normal) -> bool. Only faces where it returns True use the image; the others
        keep the palette (their swatch rule) through a second material slot. Default: every face uses the image.
        """
        self._texture = path
        self._texture_interp = interpolation
        self._texture_faces = faces
        return self

    # -- primitives (all coordinates in Blender space)
    def add_poly(self, points):
        """Adds a convex polygon from a list of (x, y, z) points as a triangle fan. Returns the faces."""
        pts = [Vector(p) for p in points]
        centre = sum(pts, Vector()) / len(pts)
        c = self.bm.verts.new(centre)
        ring = [self.bm.verts.new(p) for p in pts]
        faces = []
        for i in range(len(ring)):
            a, b = ring[i], ring[(i + 1) % len(ring)]
            faces.append(self.bm.faces.new((c, a, b)))
        return faces

    def add_tri(self, a, b, c):
        """Adds one triangle (three (x, y, z) points)."""
        return self.bm.faces.new([self.bm.verts.new(Vector(p)) for p in (a, b, c)])

    def add_box(self, center, size, rotation_z=0.0):
        """Adds an axis-aligned box centred on `center` with full extents `size` (x, y, z), optionally rotated about Z."""
        sx, sy, sz = size
        matrix = (Matrix.Translation(center) @ Matrix.Rotation(rotation_z, 4, "Z")
                  @ Matrix.Diagonal((sx, sy, sz, 1.0)))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=matrix)

    def add_cylinder(self, base_centre, radius_bottom, radius_top, depth, segments=12, caps=True):
        """Adds a (possibly tapered) cylinder whose bottom centre is `base_centre` and that rises `depth` in Z.
        Use radius_top=0 for a cone. Capped by default."""
        matrix = Matrix.Translation(Vector(base_centre) + Vector((0, 0, depth / 2.0)))
        bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=int(segments),
                              radius1=float(radius_bottom), radius2=float(radius_top),
                              depth=float(depth), matrix=matrix)

    def add_cone(self, base_centre, radius, depth, segments=12):
        """Adds a cone with its base centred on `base_centre` and its tip `depth` above it."""
        self.add_cylinder(base_centre, radius, 0.0, depth, segments=segments, caps=True)

    def add_icosphere(self, center, radius, subdivisions=2, scale=(1.0, 1.0, 1.0)):
        """Adds an icosphere at `center` (optionally stretched by `scale`). subdivisions 1-3 suit props and trees."""
        matrix = Matrix.Translation(center) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        bmesh.ops.create_icosphere(self.bm, subdivisions=int(subdivisions), radius=float(radius),
                                   matrix=matrix)

    def add_grid(self, fn, cols, rows):
        """Adds a cols x rows grid of quads. fn(u, v) -> (x, y, z) for u, v in 0..1 (wavy flags, sheets)."""
        verts = []
        for j in range(rows + 1):
            row = []
            for i in range(cols + 1):
                row.append(self.bm.verts.new(Vector(fn(i / cols, j / rows))))
            verts.append(row)
        for j in range(rows):
            for i in range(cols):
                self.bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))

    def add_star_tier(self, centre, outer, inner, points, z, tip_drop, phase=0.0, rng=None):
        """Adds one closed jagged branch skirt (a pine tier): `points` tips at radius `outer`, valleys at
        `inner`, tips bent down by `tip_drop` metres. The top is a fan from the centre, the underside is the
        same ring 0.25 * tip_drop lower, and a side strip joins the two rings, so the skirt has no hole.
        Faces are wound outward (top +Z, underside -Z, sides away from the axis). `rng` adds small jitter."""
        cx, cy = centre[0], centre[1]
        ring = []
        for k in range(points * 2):
            ang = phase + math.pi * k / points
            if k % 2 == 0:
                r, dz = outer, -tip_drop
                if rng is not None:
                    r *= 1.0 + rng.uniform(-0.06, 0.06)
                    dz += rng.uniform(-0.05, 0.05)
            else:
                r, dz = inner, 0.0
            ring.append((cx + r * math.cos(ang), cy + r * math.sin(ang), z + dz))
        thick = 0.25 * tip_drop
        under = [(x, y, zz - thick) for x, y, zz in ring]
        n = len(ring)
        top_v = [self.bm.verts.new(Vector(p)) for p in ring]
        bot_v = [self.bm.verts.new(Vector(p)) for p in under]
        mean_top = sum((Vector(p) for p in ring), Vector()) / n
        mean_bot = sum((Vector(p) for p in under), Vector()) / n
        c_top = self.bm.verts.new(mean_top)
        c_bot = self.bm.verts.new(mean_bot)
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((c_top, top_v[i], top_v[j]))
            self.bm.faces.new((c_bot, bot_v[j], bot_v[i]))
            self.bm.faces.new((top_v[i], bot_v[i], bot_v[j], top_v[j]))

    def add_blade(self, base, tip, width, bend=(0.0, 0.0, 0.0)):
        """Adds a tapered grass blade: two triangles from `base` (x, y, z) to `tip`, `width` across. `bend` offsets the tip."""
        bx, by, bz = base
        tx, ty, tz = tip
        dx, dy = -(ty - by), tx - bx
        length = math.hypot(dx, dy) or 1.0
        dx, dy = dx / length * width / 2.0, dy / length * width / 2.0
        tip_p = (tx + bend[0], ty + bend[1], tz + bend[2])
        a = (bx + dx, by + dy, bz)
        b = (bx - dx, by - dy, bz)
        self.add_tri(a, b, tip_p)

    # -- shaping
    def displace_noise(self, amplitude, frequency=1.0, salt=""):
        """Pushes every vertex along its normal by amplitude * value_noise(position * frequency). Deterministic.

        Applied to the shared vertices of this part before modifiers. Works best on icospheres and rock blobs.
        """
        seed = rng_for(self.asset.asset_id, "displace:" + self.name + salt, self.asset.seed).randint(0, 2 ** 31)
        self.bm.normal_update()
        for v in self.bm.verts:
            n = v.normal
            k = value_noise(v.co.x * frequency, v.co.y * frequency, v.co.z * frequency, seed)
            v.co += n * (k * amplitude)
        return self

    def transform(self, matrix):
        """Applies a 4x4 matrix to the part in place (for scaling, squashing or moving a whole blob)."""
        bmesh.ops.transform(self.bm, matrix=matrix, verts=self.bm.verts[:])
        return self

    def bevel(self, width, segments=1, angle_limit_deg=30.0):
        """Queues a Bevel modifier applied at finish(). Only edges sharper than angle_limit_deg are bevelled.
        Keeps the flat look; use it on props, trunks and rock shards."""
        self._modifiers.append(("BEVEL", {"width": float(width), "segments": int(segments),
                                          "angle_limit_deg": float(angle_limit_deg)}))
        return self

    def decimate(self, ratio):
        """Queues a Collapse Decimate modifier (ratio 0-1) applied at finish(). Used for rocks."""
        self._modifiers.append(("DECIMATE", {"ratio": float(ratio)}))
        return self


# ---------------------------------------------------------------- asset
class Asset:
    """One model: named parts plus its settings. finish() bakes, exports and returns the manifest entry."""

    def __init__(self, asset_id, family, seed=0, pivot="base", ao_distance=0.3, visual_only=None,
                 bake_samples=64):
        if pivot not in ("base", "rim", "sunk"):
            raise ValueError("pivot must be base, rim or sunk")
        self.asset_id = asset_id
        self.family = family
        self.seed = int(seed)
        self.pivot = pivot
        self.ao_distance = float(ao_distance)
        self.visual_only = visual_only
        self.bake_samples = int(bake_samples)
        self._parts = {}

    def part(self, name, origin=None):
        """Returns the Part called `name`, creating it on first use. Part names must be unique in the asset.

        origin: optional (x, y, z) in Blender space. The part's object origin (the glTF node translation) is
        put there while its mesh stays at the same place in the world. Use it to pivot a part, e.g. the flag
        cloth at the pole edge where it attaches. Default: the object origin is the asset origin."""
        if name not in self._parts:
            self._parts[name] = Part(self, name)
        if origin is not None:
            self._parts[name]._origin = tuple(float(c) for c in origin)
        return self._parts[name]

    def finish(self, out_dir, collision=None, variation=None, max_triangles=None):
        """Builds the Blender objects, applies modifiers, aligns the pivot, bakes AO, exports the .glb and
        returns the manifest entry. Removes everything it created from the scene afterwards.

        collision: None (visual only), a dict from tree_collision / cylinder_collision / sphere_collision.
        variation: {"scale": [a, b], "random_yaw": bool, "palettes": [...]}; defaults to unscaled, default palette.
        """
        if not self._parts:
            raise ValueError("asset %s has no parts" % self.asset_id)
        for part in self._parts.values():
            if len(part.bm.faces) == 0:
                raise ValueError("part %s of %s has no faces" % (part.name, self.asset_id))
        os.makedirs(out_dir, exist_ok=True)
        scene = _setup_render(self.ao_distance, self.bake_samples)
        created = []

        root = bpy.data.objects.new(self.asset_id, None)
        root.empty_display_type = "PLAIN_AXES"
        _link(root)
        created.append(root)

        # 1. build the mesh objects and apply modifiers
        objects = {}
        for name, part in self._parts.items():
            mesh = bpy.data.meshes.new("%s.%s" % (self.asset_id, name))
            part.bm.to_mesh(mesh)
            part.bm.free()
            obj = _link(bpy.data.objects.new(name, mesh))
            obj.parent = root
            created.append(obj)
            objects[name] = obj
            for kind, opts in part._modifiers:
                mod = obj.modifiers.new(kind.title(), kind)
                if kind == "BEVEL":
                    mod.width = opts["width"]
                    mod.segments = opts["segments"]
                    mod.limit_method = "ANGLE"
                    mod.angle_limit = math.radians(opts["angle_limit_deg"])
                    mod.harden_normals = False
                elif kind == "DECIMATE":
                    mod.decimate_type = "COLLAPSE"
                    mod.ratio = opts["ratio"]
            if obj.modifiers:
                _apply_modifiers(obj)

        # 2. pivot alignment: move the asset so the pivot rule holds, and place each part's object origin.
        # Before this step every object sits at the identity location, so local == world.
        lo, hi = _bounds_z(objects.values())
        if self.pivot == "base":
            shift = -lo
        elif self.pivot == "rim":
            shift = -hi
        else:
            shift = 0.0
        for name, obj in objects.items():
            origin = self._parts[name]._origin
            if origin is None:
                # Default: mesh data carries the shift, object origin stays at the asset origin.
                obj.data.transform(Matrix.Translation((0.0, 0.0, shift)))
            else:
                # Object origin at the chosen point (shifted with the pivot); mesh data stays in the world.
                obj.location = Vector((origin[0], origin[1], origin[2] + shift))
                obj.data.transform(Matrix.Translation((-origin[0], -origin[1], -origin[2])))
        lo, hi = _bounds_z(objects.values())
        if self.pivot == "sunk" and not (lo <= 0.0 and hi >= 0.2):
            raise ValueError("sunk pivot %s must span Z=0 (lo %.3f hi %.3f)" % (self.asset_id, lo, hi))

        # 3. triangulate, assign swatch UVs by rule, flat shade, add AO colour attribute
        triangles = 0
        for name, obj in objects.items():
            part = self._parts[name]
            _finalize_mesh(obj, part)
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
            attr = obj.data.color_attributes.new(name="AO", type="FLOAT_COLOR", domain="POINT")
            obj.data.color_attributes.active_color = attr
            obj.data.color_attributes.render_color_index = obj.data.color_attributes.find("AO")

        # 4. bake ambient occlusion into the AO vertex colours, with a ground plane as occluder
        ground = _make_ground(-0.02)
        created.append(ground)
        _bake_ao(scene, list(objects.values()))
        bpy.data.objects.remove(ground, do_unlink=True)
        created.remove(ground)
        _remap_ao(list(objects.values()))

        # 5. materials: one shared palette material per asset (plates get their own)
        palette = os.path.join(PALETTE_DIR, PALETTE_FILES["default"])
        mats = {}
        for name, obj in objects.items():
            part = self._parts[name]
            # Slot 0: the part's own image (or the palette). Slot 1 (only when texture_faces is set): the palette.
            keys = [part._texture or palette]
            if part._texture is not None and part._texture_faces is not None:
                keys.append(palette)
            # clear() resets every face's material index to 0, so keep the per-face slots and restore them.
            slot_of_face = [pg.material_index for pg in obj.data.polygons]
            obj.data.materials.clear()
            for key in keys:
                if key not in mats:
                    kind = "palette" if key == palette else "plate"
                    label = "%s_%s" % (self.asset_id, kind)
                    interp = part._texture_interp if key == part._texture else "Closest"
                    mats[key] = _make_material(label + "_" + str(len(mats)), key, interp)
                obj.data.materials.append(mats[key])
            for pg, slot in zip(obj.data.polygons, slot_of_face):
                pg.material_index = slot

        # 6. export: selected objects only (the root empty and its children)
        glb_path = os.path.join(out_dir, self.asset_id + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        for obj in created:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.ops.export_scene.gltf(
            filepath=glb_path, export_format="GLB", use_selection=True, export_yup=True,
            export_apply=False, export_materials="EXPORT", export_vertex_color="ACTIVE",
            export_image_format="AUTO", export_normals=True, export_texcoords=True,
            export_cameras=False, export_lights=False, export_animations=False)
        if not os.path.isfile(glb_path):
            raise RuntimeError("export produced no file: %s" % glb_path)

        # 7. manifest entry (sizes in Godot axes: x, y up, z)
        mins, maxs = _bounds_xyz(objects.values())
        size = [round(maxs[0] - mins[0], 3), round(maxs[2] - mins[2], 3), round(maxs[1] - mins[1], 3)]
        collision_out = _resolve_collision(collision, objects, self.asset_id, self.seed)
        visual = self.visual_only if self.visual_only is not None else (collision_out is None)
        entry = {
            "id": self.asset_id,
            "family": self.family,
            "file": to_res(glb_path),
            "size": size,
            "triangles": triangles,
            "visual_only": bool(visual),
            "collision": collision_out,
            "variation": variation or {"scale": [1.0, 1.0], "random_yaw": False,
                                       "palettes": ["default"]},
            "parts": list(self._parts.keys()),
            "pivot": self.pivot,
        }
        if max_triangles is not None:
            entry["max_triangles"] = int(max_triangles)

        # 8. remove everything this asset created from the scene
        meshes = [obj.data for obj in created if obj.type == "MESH"]
        for obj in created:
            if obj.name in bpy.data.objects:
                bpy.data.objects.remove(obj, do_unlink=True)
        for mesh in meshes:
            if mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        for mat in mats.values():
            if mat.users == 0:
                bpy.data.materials.remove(mat)
        return entry


def _apply_modifiers(obj):
    """Replaces obj's mesh with its modifier-evaluated mesh and removes the modifiers."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    new_mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True,
                                               depsgraph=depsgraph)
    old_mesh = obj.data
    old_name = old_mesh.name
    obj.modifiers.clear()
    obj.data = new_mesh
    bpy.data.meshes.remove(old_mesh)
    new_mesh.name = old_name


def _finalize_mesh(obj, part):
    """Triangulates, sets each face's UV and material slot, and flat shades.

    Faces that use the part's own image get uv_from(); all other faces get their palette swatch UV (by the
    part rule). Rules and uv functions receive world coordinates (mesh coordinates plus the object origin).
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    uv = bm.loops.layers.uv.verify()
    bm.normal_update()
    offset = obj.location.copy()
    two_slots = part._texture is not None and part._texture_faces is not None
    for face in bm.faces:
        centre = face.calc_center_median() + offset
        normal = face.normal.copy()
        textured = part._texture is not None and (part._texture_faces is None or part._texture_faces(normal))
        if textured and part._uv_fn is not None:
            for loop in face.loops:
                loop[uv].uv = part._uv_fn(loop.vert.co + offset, normal)
        else:
            index = part._rule(normal, centre)
            u, v = swatch_uv(index)
            for loop in face.loops:
                loop[uv].uv = (u, v)
        face.material_index = 0 if (textured or not two_slots) else 1
        face.smooth = False
    bm.to_mesh(obj.data)
    bm.free()
    for poly in obj.data.polygons:
        poly.use_smooth = False


def _world_points(obj):
    """World-space vertex positions of obj (its object origin is a pure translation)."""
    return [obj.location + v.co for v in obj.data.vertices]


def _bounds_z(objects):
    zs = [p.z for obj in objects for p in _world_points(obj)]
    return min(zs), max(zs)


def _bounds_xyz(objects):
    pts = [p for obj in objects for p in _world_points(obj)]
    mins = [min(p[i] for p in pts) for i in range(3)]
    maxs = [max(p[i] for p in pts) for i in range(3)]
    return mins, maxs


def _bake_ao(scene, objects):
    """Bakes ambient occlusion (Cycles) into the active colour attribute of every object."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS", use_clear=True)
    bpy.ops.object.select_all(action="DESELECT")


def _remap_ao(objects):
    """Remaps the baked AO over the whole asset so the darkest crease is 0.55 and open surfaces are 1.0."""
    arrays = []
    values = []
    for obj in objects:
        attr = obj.data.color_attributes["AO"]
        buf = [0.0] * (len(attr.data) * 4)
        attr.data.foreach_get("color", buf)
        arrays.append((attr, buf))
        values.extend(buf[0::4])
    lo = min(values) if values else 0.0
    span = max(1e-4, 1.0 - lo)
    for attr, buf in arrays:
        for i in range(0, len(buf), 4):
            t = (buf[i] - lo) / span
            t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
            v = 0.55 + 0.45 * t
            buf[i] = buf[i + 1] = buf[i + 2] = v
            buf[i + 3] = 1.0
        attr.data.foreach_set("color", buf)


def _resolve_collision(collision, objects, asset_id, asset_seed):
    if collision is None:
        return None
    if collision.get("kind") != "tree":
        return collision
    trunk_name = collision["trunk"]
    canopy_names = collision["canopy"]
    crowns = int(collision.get("crowns", 1))
    rng = rng_for(asset_id, "crowns", asset_seed + int(collision.get("seed", 0)))
    trunk_pts = [to_godot(p) for p in _world_points(objects[trunk_name])]
    canopy_pts = [to_godot(p) for name in canopy_names for p in _world_points(objects[name])]
    trunk_radius = max(math.hypot(p[0], p[2]) for p in trunk_pts)
    trunk_height = min(p[1] for p in canopy_pts)
    fitted = _fit_crowns(canopy_pts, crowns, rng)
    return {
        "kind": "tree",
        "trunk_radius": round(trunk_radius, 3),
        "trunk_height": round(trunk_height, 3),
        "crowns": [{"center": [round(c[0], 3), round(c[1], 3), round(c[2], 3)], "radius": round(r, 3)}
                   for c, r in fitted],
    }


def _fit_crowns(points, k, rng, iterations=12):
    """Deterministic k-means over canopy vertices; each crown radius reaches its farthest point plus 0.05 m."""
    k = max(1, min(3, k, len(points)))
    centres = [list(p) for p in rng.sample(points, k)]
    for _ in range(iterations):
        groups = [[] for _ in range(k)]
        for p in points:
            best = min(range(k), key=lambda i: sum((p[j] - centres[i][j]) ** 2 for j in range(3)))
            groups[best].append(p)
        for i, group in enumerate(groups):
            if group:
                centres[i] = [sum(q[j] for q in group) / len(group) for j in range(3)]
    out = []
    for i in range(k):
        group = [p for p in points if min(range(k), key=lambda j: sum((p[t] - centres[j][t]) ** 2 for t in range(3))) == i]
        group = group or points
        radius = max(math.dist(p, centres[i]) for p in group) + 0.05
        out.append((tuple(centres[i]), max(radius, 0.1)))
    return out


def tree_collision(trunk, canopy, crowns=2, seed=0):
    """Tree collision spec: trunk cylinder up to where the canopy starts, plus 1-3 crown spheres fitted to the
    canopy vertices. `trunk` is a part name, `canopy` a list of part names. Resolved in finish()."""
    return {"kind": "tree", "trunk": trunk, "canopy": list(canopy), "crowns": int(crowns), "seed": int(seed)}


def cylinder_collision(radius, height):
    """Cylinder collision (e.g. a flagstick): radius and height in metres, base at the model origin."""
    return {"kind": "cylinder", "radius": float(radius), "height": float(height)}


def sphere_collision(center, radius):
    """Sphere collision with a centre in Godot space (metres) and a radius."""
    return {"kind": "sphere", "center": [float(c) for c in center], "radius": float(radius)}
