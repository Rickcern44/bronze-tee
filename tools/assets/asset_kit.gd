## Shared toolkit for the Bronze Tee asset pipeline (phase 1). Static helpers only.
##
## USAGE EXAMPLE: a family generator (tools/assets/families/trees.gd) building a two-part tree:
##
##   extends RefCounted
##   func build(out_dir: String) -> Array:
##       var mat: StandardMaterial3D = AssetKit.make_material()        # default palette
##       var root: Node3D = AssetKit.new_root("tree_demo_a_medium")     # root name = asset id
##       # 1) trunk: 8-sided tapered cylinder, flat palette swatch 0 (trunk), with caps
##       var trunk: AssetKit.Builder = AssetKit.Builder.new()
##       AssetKit.add_cylinder(trunk, Transform3D.IDENTITY, 8, 0.35, 0.25, 4.0, true, AssetKit.TRUNK)
##       AssetKit.add_part(root, "Trunk", trunk.commit(mat))
##       # 2) canopy: seeded noisy icosphere (radius 2.6, 1 subdivision), leaves shaded by facing
##       var canopy: AssetKit.Builder = AssetKit.Builder.new()
##       var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 5.5, 0.0))
##       var shade: Vector3i = AssetKit.shade_by_facing(AssetKit.LEAF_LIGHT, AssetKit.LEAF_MID, AssetKit.LEAF_DARK)
##       AssetKit.add_icosphere(canopy, xf, 2.6, 1, 4201, 0.12, AssetKit.LEAF_MID, shade)
##       AssetKit.add_part(root, "Canopy", canopy.commit(mat))
##       # 3) export the .glb and return its manifest entry (export_asset frees root)
##       var collision: Dictionary = {"kind": "tree", "trunk_radius": 0.35, "trunk_height": 4.0,
##               "crowns": [{"center": Vector3(0.0, 5.5, 0.0), "radius": 2.6}]}
##       return [AssetKit.export_asset(root, "trees", out_dir, {"collision": collision})]
##
## out_dir is a res:// folder such as "res://assets/models/trees" (build_all passes it).
## Conventions: units metres, +Y up, model faces -Z, origin at ground contact (base centre).
class_name AssetKit
extends RefCounted

const MODELS_DIR: String = "res://assets/models"
const PALETTE_DIR: String = "res://assets/models/palette"
const PALETTE_DEFAULT: String = "res://assets/models/palette/palette_default.png"
const PALETTE_AUTUMN: String = "res://assets/models/palette/palette_autumn.png"
const MANIFEST_PATH: String = "res://assets/models/manifest.json"
const PREVIEW_DIR: String = "res://assets/models/_previews"

## Passed as `shade` to make a primitive use facing-based swatches instead of one swatch.
const NO_SHADE: Vector3i = Vector3i(-1, -1, -1)

# Palette swatch indices (index = row * 4 + col, row 0 at the top).
const TRUNK: int = 0
const TRUNK_DARK: int = 1
const LEAF_LIGHT: int = 2
const LEAF_MID: int = 3
const LEAF_DARK: int = 4
const PINE: int = 5
const PINE_DARK: int = 6
const ROCK_LIGHT: int = 7
const ROCK_MID: int = 8
const ROCK_DARK: int = 9
const WHITE: int = 10
const FLAG_RED: int = 11
const BRONZE: int = 12
const BLUE: int = 13
const FLOWER_PINK: int = 14
const FLOWER_YELLOW: int = 15

const PALETTE_SIZE: int = 64
const PALETTE_GRID: int = 4
const SWATCH_PX: int = 16

const PALETTE_HEX: Array = [
	"#7A4E2D", "#5A3A22", "#6CC46A", "#3E9A4E",
	"#2A7240", "#2E6B3A", "#1F4F2B", "#B9B2A3",
	"#8E877A", "#6B655B", "#F4F1E6", "#F0562E",
	"#D9A066", "#3D7BD9", "#F28AB8", "#FFD15C",
]

# Unit cube faces, each as 4 corners in counter-clockwise order seen from outside.
const BOX_FACES: Array = [
	[Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
	[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
	[Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
	[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
	[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
	[Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)],
]

# Icosahedron faces (indices into the 12 base vertices built in add_icosphere).
const ICOSA_FACES: Array = [
	[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
	[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
	[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
	[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
]


# ---------------------------------------------------------------- palette and UVs

## Returns the UV at the centre of palette swatch `index` (0-15).
static func swatch_uv(index: int) -> Vector2:
	var row: int = floori(float(index) / float(PALETTE_GRID))
	var col: int = index - row * PALETTE_GRID
	return Vector2((col + 0.5) / PALETTE_GRID, (row + 0.5) / PALETTE_GRID)


## Returns the swatch for a face: light if it points up (normal.y > 0.5), dark if down (< -0.5), else mid.
static func facing_swatch(normal: Vector3, light: int, mid: int, dark: int) -> int:
	if normal.y > 0.5:
		return light
	if normal.y < -0.5:
		return dark
	return mid


## Builds the light/mid/dark triple used as the `shade` argument of the primitives.
static func shade_by_facing(light: int, mid: int, dark: int) -> Vector3i:
	return Vector3i(light, mid, dark)


## Returns the 16 hex colours of a palette (autumn swaps only leaf_light, leaf_mid, leaf_dark).
static func palette_hex(autumn: bool) -> Array:
	var hex: Array = PALETTE_HEX.duplicate()
	if autumn:
		hex[LEAF_LIGHT] = "#E8A33D"
		hex[LEAF_MID] = "#D9692B"
		hex[LEAF_DARK] = "#A8442A"
	return hex


## Writes palette_default.png and palette_autumn.png (64x64, 4x4 swatches of 16 px). Returns OK or an error.
static func write_palette_pngs() -> Error:
	var err: Error = ensure_dir(to_global(PALETTE_DIR))
	if err != OK:
		return err
	err = _write_palette(to_global(PALETTE_DEFAULT), palette_hex(false))
	if err != OK:
		return err
	return _write_palette(to_global(PALETTE_AUTUMN), palette_hex(true))


static func _write_palette(global_path: String, hex: Array) -> Error:
	var img: Image = Image.create(PALETTE_SIZE, PALETTE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 1.0))
	for i in hex.size():
		var row: int = floori(float(i) / float(PALETTE_GRID))
		var col: int = i - row * PALETTE_GRID
		img.fill_rect(Rect2i(col * SWATCH_PX, row * SWATCH_PX, SWATCH_PX, SWATCH_PX), Color(String(hex[i])))
	return img.save_png(global_path)


## Creates a StandardMaterial3D that samples the palette PNG with nearest filtering (flat, no vertex colours).
static func make_material(palette_path: String = PALETTE_DEFAULT) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var img: Image = Image.load_from_file(to_global(palette_path))
	if img == null:
		push_error("AssetKit.make_material: cannot load palette %s" % palette_path)
	else:
		mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = false
	return mat


# ---------------------------------------------------------------- flat-shaded mesh builder

## Collects flat-shaded triangles (per-triangle normals, non-indexed) and commits them to an ArrayMesh.
class Builder extends RefCounted:
	var _verts: PackedVector3Array = PackedVector3Array()
	var _normals: PackedVector3Array = PackedVector3Array()
	var _uvs: PackedVector2Array = PackedVector2Array()

	## Adds one triangle. Give a, b, c counter-clockwise when seen from outside the solid, so the
	## normal cross(b-a, c-a) points outward. `swatch` is the palette index; if `shade` is not
	## NO_SHADE, each triangle uses facing_swatch(normal, shade.x, shade.y, shade.z) and `swatch` is ignored.
	## Degenerate (zero-area) triangles are skipped. Returns false when skipped.
	func add_triangle(a: Vector3, b: Vector3, c: Vector3, swatch: int, shade: Vector3i = AssetKit.NO_SHADE) -> bool:
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			return false
		n = n.normalized()
		var s: int = swatch
		if shade.x >= 0:
			s = AssetKit.facing_swatch(n, shade.x, shade.y, shade.z)
		var uv: Vector2 = AssetKit.swatch_uv(s)
		# Godot treats clockwise triangles as front faces, so the stored winding is reversed (a, c, b).
		_push(a, n, uv)
		_push(c, n, uv)
		_push(b, n, uv)
		return true

	## Adds a quad as two triangles (a, b, c) and (a, c, d). Corners counter-clockwise seen from outside.
	func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, swatch: int, shade: Vector3i = AssetKit.NO_SHADE) -> void:
		add_triangle(a, b, c, swatch, shade)
		add_triangle(a, c, d, swatch, shade)

	## Number of triangles added so far.
	@warning_ignore("integer_division")
	func triangle_count() -> int:
		return _verts.size() / 3

	## Builds an ArrayMesh with one surface using `material` (may be null). Returns null if empty.
	func commit(material: Material = null) -> ArrayMesh:
		if _verts.is_empty():
			push_error("AssetKit.Builder.commit: no triangles added")
			return null
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if material != null:
			st.set_material(material)
		for i in _verts.size():
			st.set_normal(_normals[i])
			st.set_uv(_uvs[i])
			st.add_vertex(_verts[i])
		return st.commit()

	func _push(p: Vector3, n: Vector3, uv: Vector2) -> void:
		_verts.append(p)
		_normals.append(n)
		_uvs.append(uv)


## Adds a tapered cylinder along +Y from y=0 to y=height, transformed by `xf`.
## `r_top` may be 0 for a cone. `caps` adds bottom and top discs (a cone's top cap is degenerate and skipped).
static func add_cylinder(b: Builder, xf: Transform3D, segments: int, r_bottom: float, r_top: float, height: float, caps: bool, swatch: int, shade: Vector3i = AssetKit.NO_SHADE) -> void:
	var seg: int = maxi(segments, 3)
	var ring_bottom: Array[Vector3] = []
	var ring_top: Array[Vector3] = []
	for i in seg:
		var ang: float = TAU * float(i) / float(seg)
		var dx: float = cos(ang)
		var dz: float = sin(ang)
		ring_bottom.append(xf * Vector3(dx * r_bottom, 0.0, dz * r_bottom))
		ring_top.append(xf * Vector3(dx * r_top, height, dz * r_top))
	var centre_bottom: Vector3 = xf * Vector3.ZERO
	var centre_top: Vector3 = xf * Vector3(0.0, height, 0.0)
	for i in seg:
		var j: int = (i + 1) % seg
		b.add_quad(ring_bottom[i], ring_top[i], ring_top[j], ring_bottom[j], swatch, shade)
		if caps:
			b.add_triangle(centre_bottom, ring_bottom[i], ring_bottom[j], swatch, shade)
			b.add_triangle(centre_top, ring_top[j], ring_top[i], swatch, shade)


## Adds a cone: cylinder with a point at the top, base on y=0. `cap` adds the base disc.
static func add_cone(b: Builder, xf: Transform3D, segments: int, radius: float, height: float, cap: bool, swatch: int, shade: Vector3i = AssetKit.NO_SHADE) -> void:
	add_cylinder(b, xf, segments, radius, 0.0, height, cap, swatch, shade)


## Adds an axis-aligned box centred on the local origin, full extents `size`, transformed by `xf`.
static func add_box(b: Builder, xf: Transform3D, size: Vector3, swatch: int, shade: Vector3i = AssetKit.NO_SHADE) -> void:
	var half: Vector3 = size * 0.5
	for face in BOX_FACES:
		var pts: Array[Vector3] = []
		for corner in face:
			pts.append(xf * ((corner as Vector3) * half))
		b.add_quad(pts[0], pts[1], pts[2], pts[3], swatch, shade)


## Adds a low-poly sphere (icosphere). `subdivisions` 0-2 gives 20, 80 or 320 triangles.
## Each vertex is pushed radially by up to +/- `noise` (fraction of radius) from an RNG seeded with `rng_seed`,
## so the same seed always gives the same mesh. `xf` can scale (ellipsoids) and move the result.
@warning_ignore("integer_division")
static func add_icosphere(b: Builder, xf: Transform3D, radius: float, subdivisions: int, rng_seed: int, noise: float, swatch: int, shade: Vector3i = AssetKit.NO_SHADE) -> void:
	var phi: float = (1.0 + sqrt(5.0)) * 0.5
	var raw: Array[Vector3] = [
		Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1),
	]
	var verts: Array = []
	for v in raw:
		verts.append(v.normalized())
	var faces: Array = ICOSA_FACES.duplicate(true)
	for _level in clampi(subdivisions, 0, 4):
		var cache: Dictionary = {}
		var next_faces: Array = []
		for f in faces:
			var ia: int = f[0]
			var ib: int = f[1]
			var ic: int = f[2]
			var ab: int = _midpoint(verts, cache, ia, ib)
			var bc: int = _midpoint(verts, cache, ib, ic)
			var ca: int = _midpoint(verts, cache, ic, ia)
			next_faces.append([ia, ab, ca])
			next_faces.append([ib, bc, ab])
			next_faces.append([ic, ca, bc])
			next_faces.append([ab, bc, ca])
		faces = next_faces
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var pos: Array[Vector3] = []
	for v in verts:
		var r: float = 1.0 + noise * (rng.randf() * 2.0 - 1.0)
		pos.append((v as Vector3) * (r * radius))
	for f in faces:
		var p0: Vector3 = pos[f[0]]
		var p1: Vector3 = pos[f[1]]
		var p2: Vector3 = pos[f[2]]
		# Make every face wind outward (faces above come from a list with mixed orientation).
		var centre: Vector3 = (p0 + p1 + p2) / 3.0
		if (p1 - p0).cross(p2 - p0).dot(centre) < 0.0:
			var tmp: Vector3 = p1
			p1 = p2
			p2 = tmp
		b.add_triangle(xf * p0, xf * p1, xf * p2, swatch, shade)


static func _midpoint(verts: Array, cache: Dictionary, i: int, j: int) -> int:
	var key: int = mini(i, j) * 100000 + maxi(i, j)
	if cache.has(key):
		return cache[key]
	var mid: Vector3 = ((verts[i] as Vector3) + (verts[j] as Vector3)).normalized()
	verts.append(mid)
	var idx: int = verts.size() - 1
	cache[key] = idx
	return idx


# ---------------------------------------------------------------- scene and export helpers

## Creates an empty Node3D root named `asset_id`. Children are added with add_part.
static func new_root(asset_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = asset_id
	return root


## Adds a MeshInstance3D named `part_name` under `root` (owner set so GLTF export includes it).
static func add_part(root: Node3D, part_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	return mi


## Exports the scene under `root` to a .glb at `path` (res:// or absolute). Creates folders as needed.
static func export_glb(root: Node3D, path: String) -> Error:
	var out_path: String = to_global(path)
	var err: Error = ensure_dir(out_path.get_base_dir())
	if err != OK:
		return err
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	err = doc.append_from_scene(root, state)
	if err != OK:
		return err
	return doc.write_to_filesystem(state, out_path)


## Exports `root` to out_dir/<root name>.glb and returns its manifest entry Dictionary.
## Frees `root` afterwards. Returns an empty Dictionary on failure (build_all counts that as an error).
## opts (all optional):
##   "collision": Dictionary or null (kinds: "tree", "cylinder", "sphere"; see the spec)
##   "visual_only": bool (default: true when collision is null, else false)
##   "variation": Dictionary merged over {"scale": [1,1], "random_yaw": false, "palettes": ["default"]}
##   "pivot": "rim" or "sunk" when the default ground pivot does not apply
static func export_asset(root: Node3D, family: String, out_dir: String, opts: Dictionary = {}) -> Dictionary:
	var asset_id: String = String(root.name)
	var file: String = out_dir.path_join(asset_id + ".glb")
	var err: Error = export_glb(root, file)
	if err != OK:
		push_error("AssetKit.export_asset: export failed for %s (%s): %s" % [asset_id, file, error_string(err)])
		root.free()
		return {}
	var parts: Array = []
	var bounds := AABB()
	var has_bounds: bool = false
	var tris: int = 0
	for item in flatten_meshes(root):
		var mi: MeshInstance3D = item["node"]
		var xf: Transform3D = item["xform"]
		parts.append(String(mi.name))
		if mi.mesh == null:
			continue
		var box: AABB = xf * mi.mesh.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
		tris += count_mesh_triangles(mi.mesh)
	var collision: Variant = opts.get("collision", null)
	var visual_only: bool = bool(opts.get("visual_only", collision == null))
	var variation: Dictionary = {"scale": [1.0, 1.0], "random_yaw": false, "palettes": ["default"]}
	variation.merge(opts.get("variation", {}), true)
	var entry: Dictionary = {
		"id": asset_id,
		"family": family,
		"file": file,
		"size": [snappedf(bounds.size.x, 0.001), snappedf(bounds.size.y, 0.001), snappedf(bounds.size.z, 0.001)],
		"triangles": tris,
		"visual_only": visual_only,
		"collision": collision,
		"variation": variation,
		"parts": parts,
	}
	if opts.has("pivot"):
		entry["pivot"] = opts["pivot"]
	root.free()
	return entry


## Loads a .glb with GLTFDocument (no editor import needed). Returns the generated root or null.
static func load_glb_scene(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(to_global(path), state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## Returns every MeshInstance3D under `root` as Dictionaries {"node": MeshInstance3D, "xform": Transform3D}.
## xform maps the mesh's local space into root space. Root's own transform is not applied.
static func flatten_meshes(root: Node3D) -> Array:
	var out: Array = []
	_collect_meshes(root, Transform3D.IDENTITY, out)
	return out


static func _collect_meshes(node: Node, xf: Transform3D, out: Array) -> void:
	for child in node.get_children():
		if child is Node3D:
			var cx: Transform3D = xf * (child as Node3D).transform
			if child is MeshInstance3D:
				out.append({"node": child, "xform": cx})
			_collect_meshes(child, cx, out)


## Combined bounding box of all meshes under `root`, in root space.
static func mesh_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var has: bool = false
	for item in flatten_meshes(root):
		var mi: MeshInstance3D = item["node"]
		if mi.mesh == null:
			continue
		var box: AABB = (item["xform"] as Transform3D) * mi.mesh.get_aabb()
		result = box if not has else result.merge(box)
		has = true
	return result


## Triangles in a mesh: index count / 3 per surface, or vertex count / 3 when not indexed.
@warning_ignore("integer_division")
static func count_mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and (indices as PackedInt32Array).size() > 0:
			total += (indices as PackedInt32Array).size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += verts.size() / 3
	return total


## Reads and parses manifest.json. Returns an empty Dictionary if missing or invalid.
## The family named by a `-- --family=<name>` command-line argument, or "" for a full build.
## Lets several people build, validate and preview one family at a time without touching the others.
static func family_filter() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--family="):
			return arg.trim_prefix("--family=").strip_edges()
	return ""


## The manifest this run reads and writes: the shared manifest.json for a full build, or
## assets/models/<family>/manifest.partial.json when a family filter is set.
static func manifest_path() -> String:
	var family: String = family_filter()
	if family.is_empty():
		return MANIFEST_PATH
	return "%s/%s/manifest.partial.json" % [MODELS_DIR, family]


static func read_manifest() -> Dictionary:
	var path: String = to_global(manifest_path())
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


## Converts Vector2/Vector3/Color/Vector2i/Vector3i values (recursively) into plain arrays for JSON.
static func to_json_safe(value: Variant) -> Variant:
	var t: int = typeof(value)
	if t == TYPE_VECTOR2:
		var v2: Vector2 = value
		return [v2.x, v2.y]
	if t == TYPE_VECTOR3:
		var v3: Vector3 = value
		return [v3.x, v3.y, v3.z]
	if t == TYPE_VECTOR2I:
		var i2: Vector2i = value
		return [i2.x, i2.y]
	if t == TYPE_VECTOR3I:
		var i3: Vector3i = value
		return [i3.x, i3.y, i3.z]
	if t == TYPE_COLOR:
		var c: Color = value
		return [c.r, c.g, c.b, c.a]
	if t == TYPE_DICTIONARY:
		var out_d: Dictionary = {}
		for k in value:
			out_d[k] = to_json_safe(value[k])
		return out_d
	if t == TYPE_ARRAY:
		var out_a: Array = []
		for item in value:
			out_a.append(to_json_safe(item))
		return out_a
	return value


## Converts a res:// path to an absolute filesystem path. Other paths are returned unchanged.
static func to_global(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


## Creates a directory (absolute path) and its parents if missing.
static func ensure_dir(global_dir: String) -> Error:
	if DirAccess.dir_exists_absolute(global_dir):
		return OK
	return DirAccess.make_dir_recursive_absolute(global_dir)
