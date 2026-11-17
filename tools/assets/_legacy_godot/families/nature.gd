## NATURE family: rocks and shrubs (all visual_only). Built only from AssetKit helpers.
## Output: assets/models/nature/*.glb. Deterministic: every seed is fixed.
extends RefCounted

const FAMILY: String = "nature"
const FLAT_ROCK_Y: float = 0.68
const GOLDEN_ANGLE: float = 2.39996


func build(out_dir: String) -> Array:
	var mat: StandardMaterial3D = AssetKit.make_material()
	var out: Array = []
	# Rocks: small / medium on the ground, large sunk 18% of their height below ground.
	out.append(_rock(out_dir, mat, "rock_small_a", 0.4, false, 4101, 0.0))
	out.append(_rock(out_dir, mat, "rock_small_b", 0.4, true, 4102, 0.0))
	out.append(_rock(out_dir, mat, "rock_medium_a", 0.9, false, 4201, 0.0))
	out.append(_rock(out_dir, mat, "rock_medium_b", 0.9, true, 4202, 0.0))
	out.append(_rock(out_dir, mat, "rock_large_a", 1.8, false, 4301, 0.18))
	out.append(_rock(out_dir, mat, "rock_large_b", 1.8, true, 4302, 0.18))
	# Shrubs.
	out.append(_shrub_round(out_dir, mat, "shrub_round_a", 0, 5101))
	out.append(_shrub_round(out_dir, mat, "shrub_round_b", 1, 5201))
	out.append(_shrub_flowering(out_dir, mat, "shrub_flowering_a", 0, 5301, AssetKit.FLOWER_PINK))
	out.append(_shrub_flowering(out_dir, mat, "shrub_flowering_b", 1, 5401, AssetKit.FLOWER_YELLOW))
	out.append(_grass(out_dir, mat, "shrub_grass_a", 5501, 20, 0.8, 0.25, 0.6))
	out.append(_grass(out_dir, mat, "shrub_grass_b", 5601, 24, 0.95, 0.05, 0.25))
	return out


# ---------------------------------------------------------------- rocks

func _rock(out_dir: String, mat: StandardMaterial3D, id: String, across: float, two_lobe: bool, rng_seed: int, sink_frac: float) -> Dictionary:
	var root: Node3D = AssetKit.new_root(id)
	var b := AssetKit.Builder.new()
	var shade: Vector3i = AssetKit.shade_by_facing(AssetKit.ROCK_LIGHT, AssetKit.ROCK_MID, AssetKit.ROCK_DARK)
	var flat := Basis.from_scale(Vector3(1.0, FLAT_ROCK_Y, 1.0))
	if two_lobe:
		# Two overlapping lobes make a boulder silhouette distinct from the single-lump rock.
		AssetKit.add_icosphere(b, Transform3D(flat, Vector3(-0.2, 0.0, 0.0)), 0.5, 1, rng_seed, 0.18, AssetKit.ROCK_MID, shade)
		AssetKit.add_icosphere(b, Transform3D(flat, Vector3(0.3, 0.0, 0.12)), 0.4, 1, rng_seed + 1, 0.18, AssetKit.ROCK_MID, shade)
	else:
		AssetKit.add_icosphere(b, Transform3D(flat, Vector3.ZERO), 0.5, 1, rng_seed, 0.2, AssetKit.ROCK_MID, shade)
	AssetKit.add_part(root, "Body", b.commit(mat))
	var bb: AABB = AssetKit.mesh_bounds(root)
	var s: float = across / maxf(bb.size.x, bb.size.z)
	_place(root, bb, s, sink_frac)
	var opts: Dictionary = {"variation": _variation(0.8, 1.25, ["default"])}
	if sink_frac > 0.0:
		opts["pivot"] = "sunk"
	return AssetKit.export_asset(root, FAMILY, out_dir, opts)


# ---------------------------------------------------------------- shrubs

func _shrub_round(out_dir: String, mat: StandardMaterial3D, id: String, variant: int, rng_seed: int) -> Dictionary:
	var root: Node3D = AssetKit.new_root(id)
	var b := AssetKit.Builder.new()
	_bush_body(b, _bush_layout(variant), rng_seed)
	AssetKit.add_part(root, "Body", b.commit(mat))
	var bb: AABB = AssetKit.mesh_bounds(root)
	_place(root, bb, 1.0 / maxf(bb.size.x, bb.size.z), 0.0)
	return _entry_shrub(out_dir, root)


func _shrub_flowering(out_dir: String, mat: StandardMaterial3D, id: String, variant: int, rng_seed: int, flower_swatch: int) -> Dictionary:
	var root: Node3D = AssetKit.new_root(id)
	var layout: Array = _bush_layout(variant)
	var b := AssetKit.Builder.new()
	_bush_body(b, layout, rng_seed)
	AssetKit.add_part(root, "Body", b.commit(mat))
	var fb := AssetKit.Builder.new()
	_flowers(fb, layout, rng_seed + 900, flower_swatch, 15)
	AssetKit.add_part(root, "Flowers", fb.commit(mat))
	var bb: AABB = AssetKit.mesh_bounds(root)
	_place(root, bb, 1.0 / maxf(bb.size.x, bb.size.z), 0.0)
	return _entry_shrub(out_dir, root)


func _grass(out_dir: String, mat: StandardMaterial3D, id: String, rng_seed: int, count: int, height: float, lean_lo: float, lean_hi: float) -> Dictionary:
	var root: Node3D = AssetKit.new_root(id)
	var b := AssetKit.Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in count:
		_blade(b, rng, i, height, lean_lo, lean_hi)
	AssetKit.add_part(root, "Body", b.commit(mat))
	var bb: AABB = AssetKit.mesh_bounds(root)
	_place(root, bb, height / bb.size.y, 0.0)
	return AssetKit.export_asset(root, FAMILY, out_dir, {"variation": _variation(0.85, 1.2, ["default"])})


func _entry_shrub(out_dir: String, root: Node3D) -> Dictionary:
	return AssetKit.export_asset(root, FAMILY, out_dir, {"variation": _variation(0.85, 1.2, ["default", "autumn"])})


## Three-sphere bush layout: each entry is [x, y, z, radius, subdivisions]. Variant 1 is a different arrangement.
func _bush_layout(variant: int) -> Array:
	if variant == 0:
		return [[0.0, 0.34, 0.0, 0.40, 1], [0.24, 0.28, 0.14, 0.31, 1], [-0.22, 0.25, -0.13, 0.27, 0]]
	return [[0.0, 0.36, 0.02, 0.37, 1], [-0.26, 0.26, 0.10, 0.31, 1], [0.18, 0.24, -0.20, 0.28, 0]]


func _bush_body(b: AssetKit.Builder, layout: Array, rng_seed: int) -> void:
	var shade: Vector3i = AssetKit.shade_by_facing(AssetKit.LEAF_LIGHT, AssetKit.LEAF_MID, AssetKit.LEAF_DARK)
	for i in layout.size():
		var l: Array = layout[i]
		AssetKit.add_icosphere(b, Transform3D(Basis.IDENTITY, Vector3(l[0], l[1], l[2])), l[3], l[4], rng_seed + i, 0.12, AssetKit.LEAF_MID, shade)


## Small icosphere blobs on the upper surface of the bush.
func _flowers(fb: AssetKit.Builder, layout: Array, rng_seed: int, swatch: int, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in count:
		var l: Array = layout[rng.randi() % layout.size()]
		var theta: float = rng.randf() * TAU
		var y: float = rng.randf_range(0.3, 0.95)
		var hr: float = sqrt(1.0 - y * y)
		var dir := Vector3(cos(theta) * hr, y, sin(theta) * hr)
		var centre := Vector3(l[0], l[1], l[2])
		var pos: Vector3 = centre + dir * (float(l[3]) * 1.02)
		AssetKit.add_icosphere(fb, Transform3D(Basis.IDENTITY, pos), 0.05, 0, rng_seed + 50 + i, 0.15, swatch)


## One tapered blade: two quads (lower LEAF_MID, tip LEAF_LIGHT), each added with both windings so it is double-sided.
func _blade(b: AssetKit.Builder, rng: RandomNumberGenerator, i: int, height: float, lean_lo: float, lean_hi: float) -> void:
	var theta: float = float(i) * GOLDEN_ANGLE + rng.randf_range(-0.2, 0.2)
	var out := Vector3(cos(theta), 0.0, sin(theta))
	var side := Vector3(-sin(theta), 0.0, cos(theta))
	var h: float = height * rng.randf_range(0.7, 1.0)
	var lean: float = rng.randf_range(lean_lo, lean_hi)
	var base: Vector3 = out * rng.randf_range(0.0, 0.06)
	var w0: float = rng.randf_range(0.09, 0.11)
	var w1: float = 0.02
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for t in [0.0, 0.5, 1.0]:
		var centre: Vector3 = base + Vector3.UP * (h * t) + out * (h * lean * t * t)
		var w: float = lerpf(w0, w1, t)
		lefts.append(centre - side * (w * 0.5))
		rights.append(centre + side * (w * 0.5))
	_double_quad(b, lefts[0], rights[0], rights[1], lefts[1], AssetKit.LEAF_MID)
	_double_quad(b, lefts[1], rights[1], rights[2], lefts[2], AssetKit.LEAF_LIGHT)


func _double_quad(b: AssetKit.Builder, a: Vector3, p: Vector3, c: Vector3, d: Vector3, swatch: int) -> void:
	b.add_quad(a, p, c, d, swatch)
	b.add_quad(a, d, c, p, swatch)


# ---------------------------------------------------------------- shared helpers

## Scales the root's parts uniformly by `s` and places them so the base centre sits at the origin.
## `sink_frac` pushes the bottom below ground by that fraction of the scaled height (0 = on the ground).
func _place(root: Node3D, bb: AABB, s: float, sink_frac: float) -> void:
	var sink: float = sink_frac * bb.size.y * s
	var pos := Vector3(
		-(bb.position.x + bb.size.x * 0.5) * s,
		-bb.position.y * s - sink,
		-(bb.position.z + bb.size.z * 0.5) * s)
	for child in root.get_children():
		if child is MeshInstance3D:
			(child as Node3D).transform = Transform3D(Basis.from_scale(Vector3.ONE * s), pos)


func _variation(lo: float, hi: float, palettes: Array) -> Dictionary:
	return {"scale": [lo, hi], "random_yaw": true, "palettes": palettes}
