## Tree family for the Bronze Tee asset pipeline: 16 low-poly trees (broadleaf, pine, poplar, ornamental).
## Each tree has a "Trunk" part (tapered cylinder plus branch stubs) and a "Canopy" part (icosphere blobs for
## broadleaf, poplar and ornamental; stacked cones for pines). Generation is seeded, so rebuilds are identical.
## Collision (kind "tree") is derived from the committed canopy vertices: trunk_height is the lowest canopy
## vertex, trunk_radius the mean trunk radius, and each crown is a sphere around one height band of the canopy
## (centroid plus the largest distance to its vertices, so every canopy vertex in that band is inside it).
extends RefCounted

const FAMILY: String = "trees"
const TREE_VARIATION: Dictionary = {"scale": [0.85, 1.15], "random_yaw": true, "palettes": ["default", "autumn"]}
const PINE_VARIATION: Dictionary = {"scale": [0.85, 1.15], "random_yaw": true, "palettes": ["default"]}

# Broadleaf: "counts" is the total blob count per size (the first blob is always the trunk-top bridge).
const BROADLEAF_VARIANTS: Dictionary = {
	"a": {"seed": 1100, "lean": 2.5, "lean_dir": 0.4, "stubs": 2, "taper": 0.62, "squash": 1.0, "spread": 1.0,
		"counts": {"medium": 4, "large": 5}},
	"b": {"seed": 1200, "lean": -3.0, "lean_dir": 2.1, "stubs": 1, "taper": 0.8, "squash": 0.82, "spread": 1.2,
		"counts": {"medium": 3, "large": 6}},
	"c": {"seed": 1300, "lean": 4.5, "lean_dir": 4.0, "stubs": 2, "taper": 0.55, "squash": 1.12, "spread": 0.85,
		"counts": {"medium": 5, "large": 4}},
}
const BROADLEAF_SIZES: Dictionary = {
	"medium": {"trunk": 3.0, "r_bot": 0.42, "centre_y": 5.9, "half_h": 1.3, "radius": 1.75, "spread": 1.5, "stub": 1.6},
	"large": {"trunk": 4.8, "r_bot": 0.58, "centre_y": 9.5, "half_h": 2.2, "radius": 2.5, "spread": 2.2, "stub": 2.4},
}

const PINE_VARIANTS: Dictionary = {
	"a": {"seed": 2100, "lean": 1.5, "lean_dir": 0.9, "segs": 8, "tiers": {"medium": 4, "tall": 6}},
	"b": {"seed": 2200, "lean": -2.0, "lean_dir": 3.0, "segs": 7, "tiers": {"medium": 5, "tall": 5}},
	"c": {"seed": 2300, "lean": 2.5, "lean_dir": 5.0, "segs": 9, "tiers": {"medium": 4, "tall": 6}},
}
const PINE_SIZES: Dictionary = {
	"medium": {"top": 11.0, "r0": 2.8, "r_top": 0.45},
	"tall": {"top": 17.0, "r0": 2.4, "r_top": 0.35},
}


func build(out_dir: String) -> Array:
	var out: Array = []
	for plan in _plans():
		out.append(_assemble(plan, out_dir))
	return out


func _plans() -> Array:
	var plans: Array = []
	for size in ["medium", "large"]:
		for v in ["a", "b", "c"]:
			plans.append(_broadleaf(v, size))
	for size in ["medium", "tall"]:
		for v in ["a", "b", "c"]:
			plans.append(_pine(v, size))
	for v in ["a", "b"]:
		plans.append(_poplar(v))
	for v in ["a", "b"]:
		plans.append(_ornamental(v))
	return plans


# ---------------------------------------------------------------- plans (pure data, no meshes)

func _broadleaf(v: String, size: String) -> Dictionary:
	var cfg: Dictionary = BROADLEAF_VARIANTS[v]
	var sz: Dictionary = BROADLEAF_SIZES[size]
	var rng := RandomNumberGenerator.new()
	var base_seed: int = int(cfg["seed"]) + (0 if size == "medium" else 50)
	rng.seed = base_seed
	var trunk_h: float = float(sz["trunk"]) * rng.randf_range(0.95, 1.05)
	var r_bot: float = float(sz["r_bot"]) * rng.randf_range(0.9, 1.1)
	var radius: float = float(sz["radius"])
	var centre_y: float = float(sz["centre_y"])
	var half_h: float = float(sz["half_h"])
	var band_lo: float = centre_y - half_h
	var band_span: float = 2.0 * half_h
	var squash: float = float(cfg["squash"])
	var spread: float = float(sz["spread"]) * float(cfg["spread"])
	var n: int = int(cfg["counts"][size])

	var canopy: Array = []
	# Bridge blob: sits over the trunk top so the canopy is attached to the trunk.
	var bridge_y: float = trunk_h + 0.3 * radius
	canopy.append(_ico(Vector3(0.0, bridge_y, 0.0), Vector3(1.0, squash, 1.0), radius * 0.9, 1, 0.14,
			base_seed, _band(bridge_y, band_lo, band_span)))
	for i in range(1, n):
		var ang: float = TAU * float(i) / float(n) + rng.randf_range(-0.35, 0.35)
		var d: float = spread * rng.randf_range(0.45, 1.0)
		var y: float = centre_y + rng.randf_range(-half_h, half_h)
		var rad: float = radius * rng.randf_range(0.82, 1.08)
		var centre := Vector3(cos(ang) * d, y, sin(ang) * d)
		canopy.append(_ico(centre, Vector3(1.0, squash, 1.0), rad, 1, 0.14, base_seed + i,
				_band(y, band_lo, band_span)))

	var stubs: Array = []
	for k in int(cfg["stubs"]):
		stubs.append({
			"az": rng.randf_range(0.0, TAU),
			"el": rng.randf_range(0.35, 0.7),
			"y": trunk_h * rng.randf_range(0.5, 0.9),
			"length": float(sz["stub"]) * rng.randf_range(0.9, 1.1),
			"r": r_bot * 0.45,
		})

	return {
		"id": "tree_broadleaf_%s_%s" % [v, size],
		"kind": "leaf",
		"lean": float(cfg["lean"]),
		"lean_dir": float(cfg["lean_dir"]),
		"trunk": {"height": trunk_h, "r_bot": r_bot, "r_top": r_bot * float(cfg["taper"]), "segs": 7},
		"stubs": stubs,
		"canopy": canopy,
		"variation": TREE_VARIATION,
	}


func _pine(v: String, size: String) -> Dictionary:
	var cfg: Dictionary = PINE_VARIANTS[v]
	var sz: Dictionary = PINE_SIZES[size]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"]) + (0 if size == "medium" else 40)
	var n: int = int(cfg["tiers"][size])
	var base0: float = 1.2
	var tip: float = 2.2
	var top: float = float(sz["top"])
	var span: float = (top - tip - base0) / float(n - 1)

	var canopy: Array = []
	for i in n:
		var t: float = float(i) / float(n - 1)
		var rad: float = lerpf(float(sz["r0"]), float(sz["r_top"]), t) * rng.randf_range(0.92, 1.08)
		var h: float = tip if i == n - 1 else span * 2.0
		var off := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var base_y: float = base0 + span * float(i)
		var group: int = clampi(int(float(i) / float(n) * 3.0), 0, 2)
		canopy.append(_cone(off + Vector3(0.0, base_y, 0.0), rad, h, int(cfg["segs"]), group))

	return {
		"id": "tree_pine_%s_%s" % [v, size],
		"kind": "pine",
		"lean": float(cfg["lean"]),
		"lean_dir": float(cfg["lean_dir"]),
		"trunk": {"height": base0 + 0.5, "r_bot": 0.2, "r_top": 0.12, "segs": 6},
		"stubs": [],
		"canopy": canopy,
		"variation": PINE_VARIATION,
	}


func _poplar(v: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var base_seed: int = 3100 if v == "a" else 3200
	rng.seed = base_seed
	var canopy: Array = []
	var trunk_h: float = 2.6
	if v == "a":
		# Column of four overlapping blobs; three height bands for the crowns.
		var ys: Array = [3.2, 5.6, 8.0, 10.4]
		var groups: Array = [0, 0, 1, 2]
		for i in 4:
			var rad: float = 1.7 * rng.randf_range(0.9, 1.05)
			var c := Vector3(rng.randf_range(-0.15, 0.15), float(ys[i]), rng.randf_range(-0.15, 0.15))
			canopy.append(_ico(c, Vector3(1.0, 1.15, 1.0), rad, 1, 0.12, base_seed + i, int(groups[i])))
	else:
		# Tall narrow ellipsoid stacked with a smaller top ellipsoid.
		trunk_h = 2.4
		canopy.append(_ico(Vector3(0.0, 4.2, 0.0), Vector3(1.0, 1.7, 1.0), 1.5, 2, 0.08, base_seed, 0))
		canopy.append(_ico(Vector3(0.0, 9.2, 0.0), Vector3(1.0, 1.8, 1.0), 1.3, 2, 0.08, base_seed + 1, 1))
	return {
		"id": "tree_poplar_%s" % v,
		"kind": "leaf",
		"lean": 1.0 if v == "a" else -1.5,
		"lean_dir": 1.2 if v == "a" else 4.6,
		"trunk": {"height": trunk_h, "r_bot": 0.24, "r_top": 0.15, "segs": 6},
		"stubs": [],
		"canopy": canopy,
		"variation": TREE_VARIATION,
	}


func _ornamental(v: String) -> Dictionary:
	var canopy: Array = []
	var trunk_h: float = 1.7
	if v == "a":
		# Round crown: one smooth-ish icosphere with two smaller blobs for a lumpy outline.
		canopy.append(_ico(Vector3(0.0, 3.1, 0.0), Vector3.ONE, 1.8, 2, 0.1, 5100, 0))
		canopy.append(_ico(Vector3(1.0, 2.8, 0.45), Vector3.ONE, 0.95, 1, 0.12, 5101, 1))
		canopy.append(_ico(Vector3(-0.7, 4.0, -0.8), Vector3.ONE, 0.9, 1, 0.12, 5102, 1))
	else:
		# Wide flattened crown with three satellite blobs underneath.
		trunk_h = 2.3
		canopy.append(_ico(Vector3(0.0, 3.5, 0.0), Vector3(1.0, 0.78, 1.0), 1.8, 1, 0.12, 5200, 0))
		canopy.append(_ico(Vector3(1.3, 3.0, 0.2), Vector3.ONE, 0.95, 1, 0.12, 5201, 1))
		canopy.append(_ico(Vector3(-0.9, 3.7, 1.0), Vector3.ONE, 0.95, 1, 0.12, 5202, 1))
		canopy.append(_ico(Vector3(0.1, 4.7, -1.2), Vector3.ONE, 0.95, 1, 0.12, 5203, 1))
	var trunk := {"height": trunk_h, "r_bot": 0.15, "r_top": 0.1, "segs": 7}
	return {
		"id": "tree_ornamental_%s_small" % v,
		"kind": "leaf",
		"lean": 3.0 if v == "a" else -2.0,
		"lean_dir": 2.4 if v == "a" else 0.6,
		"trunk": trunk,
		"stubs": [],
		"canopy": canopy,
		"variation": TREE_VARIATION,
	}


# ---------------------------------------------------------------- plan helpers

func _ico(centre: Vector3, scale: Vector3, radius: float, subdiv: int, noise: float, seed: int, group: int) -> Dictionary:
	return {"type": "ico", "centre": centre, "scale": scale, "radius": radius, "subdiv": subdiv,
			"noise": noise, "seed": seed, "group": group}


func _cone(base: Vector3, radius: float, height: float, segs: int, group: int) -> Dictionary:
	return {"type": "cone", "centre": base, "radius": radius, "height": height, "segs": segs, "group": group}


## Crown group (0-2) from the height band a blob sits in.
func _band(y: float, lo: float, span: float) -> int:
	return clampi(int((y - lo) / span * 3.0), 0, 2)


# ---------------------------------------------------------------- meshes, collision and export

func _assemble(plan: Dictionary, out_dir: String) -> Dictionary:
	var id: String = plan["id"]
	var mat: StandardMaterial3D = AssetKit.make_material()
	var root: Node3D = AssetKit.new_root(id)

	# Lean: the whole tree tilts a few degrees about its base.
	var lean_dir: float = float(plan["lean_dir"])
	var lean_axis := Vector3(-sin(lean_dir), 0.0, cos(lean_dir))
	# The base rim dips below y=0 when tilted, so lift the whole tree by that dip to keep the pivot on the ground.
	var lean_rad: float = deg_to_rad(float(plan["lean"]))
	var trunk: Dictionary = plan["trunk"]
	var r_bot: float = float(trunk["r_bot"])
	var r_top: float = float(trunk["r_top"])
	var trunk_h: float = float(trunk["height"])
	var lift: float = r_bot * absf(sin(lean_rad))
	var lean := Transform3D(Basis(lean_axis, lean_rad), Vector3(0.0, lift, 0.0))

	# Trunk and branch stubs (trunk swatches: light on top, dark underneath).
	var shade_trunk: Vector3i = AssetKit.shade_by_facing(AssetKit.TRUNK, AssetKit.TRUNK, AssetKit.TRUNK_DARK)
	var tb := AssetKit.Builder.new()
	AssetKit.add_cylinder(tb, lean, int(trunk["segs"]), r_bot, r_top, trunk_h, true, AssetKit.TRUNK, shade_trunk)
	for s in plan["stubs"]:
		var az: float = float(s["az"])
		var el: float = float(s["el"])
		var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)).normalized()
		var local := Transform3D(Basis(Quaternion(Vector3.UP, dir)), Vector3(0.0, float(s["y"]), 0.0) - dir * 0.2)
		var sr: float = float(s["r"])
		AssetKit.add_cylinder(tb, lean * local, 6, sr, sr * 0.5, float(s["length"]), true, AssetKit.TRUNK, shade_trunk)

	# Canopy: leaves shaded by facing for broadleaf/poplar/ornamental, pine swatches for pines.
	var is_pine: bool = plan["kind"] == "pine"
	var swatch: int = AssetKit.PINE if is_pine else AssetKit.LEAF_MID
	var shade: Vector3i = AssetKit.shade_by_facing(AssetKit.PINE, AssetKit.PINE, AssetKit.PINE_DARK) if is_pine \
			else AssetKit.shade_by_facing(AssetKit.LEAF_LIGHT, AssetKit.LEAF_MID, AssetKit.LEAF_DARK)
	var cb := AssetKit.Builder.new()
	var ranges: Array = []
	for item in plan["canopy"]:
		var t0: int = cb.triangle_count()
		if item["type"] == "ico":
			var local_ico := Transform3D(Basis.from_scale(item["scale"]), item["centre"])
			AssetKit.add_icosphere(cb, lean * local_ico, float(item["radius"]), int(item["subdiv"]),
					int(item["seed"]), float(item["noise"]), swatch, shade)
		else:
			var local_cone := Transform3D(Basis.IDENTITY, item["centre"])
			AssetKit.add_cone(cb, lean * local_cone, int(item["segs"]), float(item["radius"]),
					float(item["height"]), true, swatch, shade)
		ranges.append([t0, cb.triangle_count(), int(item["group"])])
	var cmesh: ArrayMesh = cb.commit(mat)
	var verts: PackedVector3Array = cmesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

	# Collision from the generated geometry.
	var groups: Dictionary = {}
	var min_y: float = INF
	for v in verts:
		min_y = minf(min_y, v.y)
	for r in ranges:
		var g: int = r[2]
		if not groups.has(g):
			groups[g] = []
		var pts: Array = groups[g]
		for k in range(int(r[0]) * 3, int(r[1]) * 3):
			pts.append(verts[k])
	var keys: Array = groups.keys()
	keys.sort()
	var crowns: Array = []
	for g in keys:
		var fit: Dictionary = _fit_sphere(groups[g])
		crowns.append({"center": _snap(fit["center"]), "radius": snappedf(float(fit["radius"]) + 0.02, 0.01)})
	var collision: Dictionary = {
		"kind": "tree",
		"trunk_radius": snappedf((r_bot + r_top) * 0.5, 0.01),
		"trunk_height": snappedf(minf(min_y, trunk_h), 0.01),
		"crowns": crowns,
	}

	AssetKit.add_part(root, "Trunk", tb.commit(mat))
	AssetKit.add_part(root, "Canopy", cmesh)
	return AssetKit.export_asset(root, FAMILY, out_dir, {"collision": collision, "variation": plan["variation"]})


## Smallest-enough sphere around points: centre xz at the mean, centre height searched over the point
## range for the smallest maximum distance (a plain centroid wastes a lot of radius on tall cones).
func _fit_sphere(pts: Array) -> Dictionary:
	var mean := Vector3.ZERO
	var lo: float = INF
	var hi: float = -INF
	for p in pts:
		mean += p
		lo = minf(lo, (p as Vector3).y)
		hi = maxf(hi, (p as Vector3).y)
	mean /= float(pts.size())
	var best_c: Vector3 = mean
	var best_r: float = INF
	var steps: int = 96
	for s in range(steps + 1):
		var cc := Vector3(mean.x, lerpf(lo, hi, float(s) / float(steps)), mean.z)
		var r: float = 0.0
		for p in pts:
			r = maxf(r, (p as Vector3).distance_to(cc))
		if r < best_r:
			best_r = r
			best_c = cc
	return {"center": best_c, "radius": best_r}


func _snap(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01))
