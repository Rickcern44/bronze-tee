"""Renders previews of a family's .glb files with Blender (Cycles, CPU, headless).

Run (args after `--`):
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
        -P tools/blender/previews.py -- --family=trees
    ... -- --family=trees --palette=autumn --skip-thumbs    (autumn lineup only: _previews/autumn_trees.png)
    ... -- --family=trees --skip-lineup                      (thumbnails only)

Reads assets/models/<family>/manifest.partial.json (falls back to assets/models/manifest.json), imports each
.glb back into Blender (so the preview shows exactly what the file contains, vertex colours included) and writes:
  assets/models/_previews/thumbs/<id>.png     512x512, 3/4 view, ground disc #5AAD38
  assets/models/_previews/<family>_lineup.png 1600x900, every asset in a row with a 1.8 m white reference post
  assets/models/_previews/autumn_<family>.png same lineup with palette_autumn.png swapped in (--palette=autumn)
Contact sheets are made afterwards by contact_sheet.py (system python3 with Pillow).
Exit code 0 on success, 1 on error.
"""

import argparse
import json
import math
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import bt_kit as bt  # noqa: E402

PREVIEWS_DIR = os.path.join(bt.MODELS_DIR, "_previews")
THUMB_DIR = os.path.join(PREVIEWS_DIR, "thumbs")
SAMPLES = 48


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="previews.py")
    parser.add_argument("--family", required=True)
    parser.add_argument("--palette", default="default", choices=["default", "autumn"])
    parser.add_argument("--skip-thumbs", action="store_true")
    parser.add_argument("--skip-lineup", action="store_true")
    return parser.parse_args(argv)


def _entries(family):
    partial = os.path.join(bt.MODELS_DIR, family, "manifest.partial.json")
    if os.path.isfile(partial):
        with open(partial, encoding="utf-8") as handle:
            return json.load(handle)["assets"]
    with open(os.path.join(bt.MODELS_DIR, "manifest.json"), encoding="utf-8") as handle:
        return [e for e in json.load(handle)["assets"] if e["family"] == family]


def _glb_path(entry):
    return os.path.join(bt.PROJECT_ROOT, entry["file"].replace("res://", ""))


def _setup_scene(samples, width, height):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.62, 0.78, 0.98, 1.0)
    bg.inputs["Strength"].default_value = 0.5
    return scene


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = tuple(_srgb_to_linear(c / 255.0) for c in rgb) + (1.0,)
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def _add_mesh(name, verts_fn, material):
    bm = bmesh.new()
    verts_fn(bm)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def _add_ground(radius, z=-0.01):
    def make(bm):
        bmesh.ops.create_circle(bm, cap_ends=True, segments=72, radius=radius)
        for v in bm.verts:
            v.co.z = z
    return _add_mesh("PreviewGround", make, _material("PreviewGroundMat", (0x5A, 0xAD, 0x38)))


def _add_lights():
    sun = bpy.data.lights.new("PreviewSun", "SUN")
    sun.energy = 1.4
    sun.angle = math.radians(4.0)
    sun_obj = bpy.data.objects.new("PreviewSun", sun)
    sun_obj.rotation_euler = (math.radians(50), math.radians(8), math.radians(-35))
    bpy.context.scene.collection.objects.link(sun_obj)


def _add_camera(target, radius, azimuth_deg, elevation_deg, width, height):
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 50.0
    cam_data.sensor_width = 36.0
    cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    az, el = math.radians(azimuth_deg), math.radians(elevation_deg)
    hfov = 2.0 * math.atan(cam_data.sensor_width / 2.0 / cam_data.lens)
    vfov = 2.0 * math.atan(math.tan(hfov / 2.0) * height / width)
    # fit the bounding sphere inside the narrower of the two fields of view
    distance = radius / math.sin(min(hfov, vfov) / 2.0) * 1.12
    offset = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el))) * distance
    cam_obj.location = Vector(target) + offset
    direction = Vector(target) - cam_obj.location
    cam_obj.rotation_mode = "QUATERNION"
    cam_obj.rotation_quaternion = direction.to_track_quat("-Z", "Y")
    bpy.context.scene.camera = cam_obj
    return cam_obj


def _imported_objects(path):
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=path)
    return [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in before]


def _mesh_objects(objs):
    return [o for o in objs if o.type == "MESH"]


def _world_bounds(objs):
    pts = []
    for obj in _mesh_objects(objs):
        for v in obj.data.vertices:
            pts.append(obj.matrix_world @ v.co)
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def _swap_palette(objs, palette_image):
    """Points every palette texture node at `palette_image`. The glTF importer already multiplies COLOR_0
    (the baked AO) into the base colour, so nothing else is needed for the vertex colours."""
    seen = set()
    for obj in _mesh_objects(objs):
        for mat in obj.data.materials:
            if mat is None or mat.name in seen or not mat.use_nodes:
                continue
            seen.add(mat.name)
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE":
                    node.image = palette_image
                    node.interpolation = "Closest"


def _clear_scene():
    bt.reset_scene()
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def _render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    if not os.path.isfile(path):
        raise RuntimeError("render produced no file: %s" % path)
    print("wrote %s" % os.path.relpath(path, bt.PROJECT_ROOT))


def render_thumbs(entries):
    for entry in entries:
        _clear_scene()
        _setup_scene(SAMPLES, 512, 512)
        objs = _imported_objects(_glb_path(entry))
        lo, hi = _world_bounds(objs)
        centre = (lo + hi) / 2.0
        radius = (hi - lo).length / 2.0
        _add_ground(max(3.0, radius * 1.6))
        _add_lights()
        _add_camera(centre, radius, 55.0, 18.0, 512, 512)
        _render(os.path.join(THUMB_DIR, entry["id"] + ".png"))


def render_lineup(entries, family, palette):
    _clear_scene()
    _setup_scene(SAMPLES, 1600, 900)
    palette_image = None
    if palette == "autumn":
        palette_image = bpy.data.images.load(os.path.join(bt.PALETTE_DIR, bt.PALETTE_FILES["autumn"]),
                                             check_existing=True)
    x = 0.0
    placed = []
    gap = 1.2
    for entry in entries:
        objs = _imported_objects(_glb_path(entry))
        lo, hi = _world_bounds(objs)
        width = hi.x - lo.x
        shift = Vector((x - lo.x, 0.0, 0.0))
        for obj in objs:
            if obj.parent is None:
                obj.location += shift
        x += width + gap
        placed.append(objs)
    all_objs = [o for group in placed for o in group]
    if palette_image is not None:
        _swap_palette(all_objs, palette_image)
    bpy.context.view_layer.update()
    lo, hi = _world_bounds(all_objs)
    post = _add_mesh("ReferencePost", lambda bm: bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=12, radius1=0.03, radius2=0.03, depth=1.8,
        matrix=Matrix.Translation((0, 0, 0.9))), _material("RefPostMat", (0xF4, 0xF1, 0xE6)))
    post.location = Vector((lo.x - 1.6, 0.0, 0.0))
    bpy.context.view_layer.update()
    full_lo = Vector((lo.x - 1.6, lo.y, 0.0))
    full_hi = Vector((hi.x, hi.y, max(hi.z, 1.8)))
    centre = (full_lo + full_hi) / 2.0
    radius = max((full_hi - full_lo).length / 2.0, 1.5)
    _add_ground(max(20.0, radius * 3.0))
    _add_lights()
    _add_camera(centre, radius, 58.0, 22.0, 1600, 900)
    name = ("autumn_" + family) if palette == "autumn" else (family + "_lineup")
    _render(os.path.join(PREVIEWS_DIR, name + ".png"))


def main():
    args = _args()
    entries = _entries(args.family)
    if not entries:
        raise RuntimeError("no assets for family %s" % args.family)
    print("previewing %d assets of %s (palette %s)" % (len(entries), args.family, args.palette))
    if not args.skip_thumbs:
        render_thumbs(entries)
    if not args.skip_lineup:
        render_lineup(entries, args.family, args.palette)
    print("PREVIEWS OK")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except BaseException:
        traceback.print_exc()
        print("PREVIEWS FAILED")
        sys.exit(1)
    sys.exit(0)
