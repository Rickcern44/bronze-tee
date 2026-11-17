## Props family: flagsticks (collision), cup, tee markers and yardage markers (visual only).
## Output: assets/models/props/. Yardage plate textures come from tools/assets/make_yardage_plates.py.
extends RefCounted

const POLE_HEIGHT: float = 2.13
const POLE_RADIUS: float = 0.0125
const CUP_INNER_RADIUS: float = 0.054
const CUP_OUTER_RADIUS: float = 0.060
const CUP_DEPTH: float = 0.1016
const PLATE_TEXTURE_DIR: String = "res://assets/models/props/textures"


func build(out_dir: String) -> Array:
	var entries: Array = []
	var flags: Array = [["red", AssetKit.FLAG_RED], ["yellow", AssetKit.FLOWER_YELLOW], ["blue", AssetKit.BLUE]]
	for f in flags:
		entries.append(_flagstick(String(f[0]), int(f[1]), out_dir))
	entries.append(_cup(out_dir))
	var colours: Array = [["white", AssetKit.WHITE], ["blue", AssetKit.BLUE], ["red", AssetKit.FLAG_RED], ["gold", AssetKit.BRONZE]]
	for style in ["ball", "block", "tee"]:
		for c in colours:
			entries.append(_tee_marker(style, String(c[0]), int(c[1]), out_dir))
	var yardages: Array = [[100, AssetKit.FLAG_RED], [150, AssetKit.WHITE], [200, AssetKit.BLUE], [250, AssetKit.BRONZE]]
	for y in yardages:
		entries.append(_yardage_marker(int(y[0]), int(y[1]), out_dir))
	return entries


# ---------------------------------------------------------------- helpers

## Adds the quad p0-p1-p2-p3 (loop order) as two triangles, each oriented so its normal agrees with `hint`.
static func _quad(b: AssetKit.Builder, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, hint: Vector3, swatch: int) -> void:
	_tri(b, p0, p1, p2, hint, swatch)
	_tri(b, p0, p2, p3, hint, swatch)


## Adds one triangle, swapping two corners if needed so its normal points along `hint`.
static func _tri(b: AssetKit.Builder, a: Vector3, c1: Vector3, c2: Vector3, hint: Vector3, swatch: int) -> void:
	var n: Vector3 = (c1 - a).cross(c2 - a)
	if n.dot(hint) < 0.0:
		var tmp: Vector3 = c1
		c1 = c2
		c2 = tmp
	b.add_triangle(a, c1, c2, swatch)


static func _ring(radius: float, y: float, segments: int, i: int) -> Vector3:
	var ang: float = TAU * float(i) / float(segments)
	return Vector3(cos(ang) * radius, y, sin(ang) * radius)


static func _export(root: Node3D, out_dir: String, opts: Dictionary) -> Dictionary:
	return AssetKit.export_asset(root, "props", out_dir, opts)


# ---------------------------------------------------------------- flagsticks

func _flagstick(colour_name: String, flag_swatch: int, out_dir: String) -> Dictionary:
	var root: Node3D = AssetKit.new_root("flagstick_" + colour_name)
	var mat: StandardMaterial3D = AssetKit.make_material()

	var pole := AssetKit.Builder.new()
	AssetKit.add_cylinder(pole, Transform3D.IDENTITY, 8, POLE_RADIUS, POLE_RADIUS, POLE_HEIGHT, true, AssetKit.WHITE)
	AssetKit.add_cylinder(pole, Transform3D.IDENTITY, 8, 0.016, 0.016, 0.07, true, AssetKit.BRONZE)
	var band_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.77, 0.0))
	AssetKit.add_cylinder(pole, band_xf, 8, 0.0135, 0.0135, 0.06, true, flag_swatch)
	AssetKit.add_part(root, "Pole", pole.commit(mat))

	# Cloth: 4 x 2 quads, double-sided, hanging from the top of the pole edge (node origin).
	var cloth := AssetKit.Builder.new()
	var cols: int = 4
	var rows: int = 2
	for c in cols:
		for r in rows:
			var p00: Vector3 = _cloth_point(float(c) / cols, float(r) / rows)
			var p10: Vector3 = _cloth_point(float(c + 1) / cols, float(r) / rows)
			var p11: Vector3 = _cloth_point(float(c + 1) / cols, float(r + 1) / rows)
			var p01: Vector3 = _cloth_point(float(c) / cols, float(r + 1) / rows)
			_quad(cloth, p00, p10, p11, p01, Vector3(0.0, 0.0, 1.0), flag_swatch)
			_quad(cloth, p00, p10, p11, p01, Vector3(0.0, 0.0, -1.0), flag_swatch)
	var flag_node: MeshInstance3D = AssetKit.add_part(root, "Flag", cloth.commit(mat))
	flag_node.position = Vector3(POLE_RADIUS, 2.10, 0.0)

	var collision: Dictionary = {"kind": "cylinder", "radius": POLE_RADIUS, "height": POLE_HEIGHT}
	return _export(root, out_dir, {"collision": collision, "visual_only": false})


## Cloth point in Flag space: u 0 at the pole edge to 1 at the free edge, v 0 at the top to 1 at the bottom.
static func _cloth_point(u: float, v: float) -> Vector3:
	return Vector3(0.5 * u, -0.35 * v, 0.03 * sin(u * PI * 1.5))


# ---------------------------------------------------------------- cup

func _cup(out_dir: String) -> Dictionary:
	var root: Node3D = AssetKit.new_root("cup")
	var mat: StandardMaterial3D = AssetKit.make_material()
	var liner := AssetKit.Builder.new()
	var seg: int = 12
	var d: float = -CUP_DEPTH
	var zero := Vector3.ZERO
	var bottom_centre := Vector3(0.0, d, 0.0)
	for i in seg:
		var j: int = (i + 1) % seg
		var mid: float = TAU * (float(i) + 0.5) / float(seg)
		var radial := Vector3(cos(mid), 0.0, sin(mid))
		# Inner wall: faces inward (towards the axis), dark.
		_quad(liner, _ring(CUP_INNER_RADIUS, 0.0, seg, i), _ring(CUP_INNER_RADIUS, d, seg, i),
				_ring(CUP_INNER_RADIUS, d, seg, j), _ring(CUP_INNER_RADIUS, 0.0, seg, j), -radial, AssetKit.ROCK_DARK)
		# Outer wall: faces outward, mid rock.
		_quad(liner, _ring(CUP_OUTER_RADIUS, 0.0, seg, i), _ring(CUP_OUTER_RADIUS, 0.0, seg, j),
				_ring(CUP_OUTER_RADIUS, d, seg, j), _ring(CUP_OUTER_RADIUS, d, seg, i), radial, AssetKit.ROCK_MID)
		# White rim ring at y = 0, facing up.
		_quad(liner, _ring(CUP_INNER_RADIUS, 0.0, seg, i), _ring(CUP_OUTER_RADIUS, 0.0, seg, i),
				_ring(CUP_OUTER_RADIUS, 0.0, seg, j), _ring(CUP_INNER_RADIUS, 0.0, seg, j), Vector3.UP, AssetKit.WHITE)
		# Bottom disc, inside (up) and underside (down).
		_tri(liner, bottom_centre, _ring(CUP_OUTER_RADIUS, d, seg, i), _ring(CUP_OUTER_RADIUS, d, seg, j), Vector3.UP, AssetKit.ROCK_DARK)
		_tri(liner, bottom_centre, _ring(CUP_OUTER_RADIUS, d, seg, i), _ring(CUP_OUTER_RADIUS, d, seg, j), Vector3.DOWN, AssetKit.ROCK_MID)
	AssetKit.add_part(root, "Liner", liner.commit(mat))
	return _export(root, out_dir, {"visual_only": true, "pivot": "rim"})


# ---------------------------------------------------------------- tee markers

func _tee_marker(style: String, colour_name: String, swatch: int, out_dir: String) -> Dictionary:
	var root: Node3D = AssetKit.new_root("tee_marker_%s_%s" % [style, colour_name])
	var mat: StandardMaterial3D = AssetKit.make_material()
	var body := AssetKit.Builder.new()
	match style:
		"ball":
			AssetKit.add_icosphere(body, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.28, 0.0)), 0.28, 1, 5101, 0.03, swatch)
		"block":
			_block(body, swatch)
		"tee":
			_tee(body, swatch)
	AssetKit.add_part(root, "Body", body.commit(mat))
	var variation: Dictionary = {"scale": [0.95, 1.05], "random_yaw": false}
	return _export(root, out_dir, {"visual_only": true, "variation": variation})


## Box 0.30 wide, 0.22 tall, 0.22 deep, with the top edges chamfered by 0.04 m.
static func _block(b: AssetKit.Builder, swatch: int) -> void:
	var half_w: float = 0.15
	var half_d: float = 0.11
	var h: float = 0.22
	var c: float = 0.04
	var corners: Array = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var bot: Array = []
	var mid: Array = []
	var top: Array = []
	for corner in corners:
		var s: Vector2 = corner
		bot.append(Vector3(s.x * half_w, 0.0, s.y * half_d))
		mid.append(Vector3(s.x * half_w, h - c, s.y * half_d))
		top.append(Vector3(s.x * (half_w - c), h, s.y * (half_d - c)))
	for k in 4:
		var n: int = (k + 1) % 4
		var s0: Vector2 = corners[k]
		var s1: Vector2 = corners[n]
		var side_dir: Vector3 = Vector3((s0.x + s1.x) * 0.5, 0.0, (s0.y + s1.y) * 0.5).normalized()
		_quad(b, bot[k], bot[n], mid[n], mid[k], side_dir, swatch)
		var chamfer_dir: Vector3 = (side_dir + Vector3(0.0, 0.8, 0.0)).normalized()
		_quad(b, mid[k], mid[n], top[n], top[k], chamfer_dir, swatch)
	_quad(b, top[0], top[1], top[2], top[3], Vector3.UP, swatch)
	_quad(b, bot[0], bot[3], bot[2], bot[1], Vector3.DOWN, swatch)


## Giant golf tee, 0.45 m tall: tapered peg with a cupped head, built as a revolved profile.
static func _tee(b: AssetKit.Builder, swatch: int) -> void:
	var profile: Array = [
		Vector2(0.0, 0.0), Vector2(0.010, 0.04), Vector2(0.016, 0.14), Vector2(0.020, 0.27),
		Vector2(0.036, 0.31), Vector2(0.080, 0.41), Vector2(0.088, 0.45),
		Vector2(0.079, 0.44), Vector2(0.040, 0.40), Vector2(0.0, 0.39),
	]
	var seg: int = 8
	for k in profile.size() - 1:
		var p0: Vector2 = profile[k]
		var p1: Vector2 = profile[k + 1]
		# Outward normal in (radius, height): right-hand side of the travel direction.
		var nrm: Vector2 = Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
		for i in seg:
			var a0: float = TAU * float(i) / float(seg)
			var a1: float = TAU * float(i + 1) / float(seg)
			var mid: float = TAU * (float(i) + 0.5) / float(seg)
			var hint := Vector3(cos(mid) * nrm.x, nrm.y, sin(mid) * nrm.x)
			_quad(b, _rev(p0, a0), _rev(p1, a0), _rev(p1, a1), _rev(p0, a1), hint, swatch)


static func _rev(p: Vector2, ang: float) -> Vector3:
	return Vector3(cos(ang) * p.x, p.y, sin(ang) * p.x)


# ---------------------------------------------------------------- yardage markers

func _yardage_marker(distance: int, cap_swatch: int, out_dir: String) -> Dictionary:
	var root: Node3D = AssetKit.new_root("yardage_marker_%d" % distance)
	var mat: StandardMaterial3D = AssetKit.make_material()

	var post := AssetKit.Builder.new()
	var post_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.425, 0.0))
	AssetKit.add_box(post, post_xf, Vector3(0.12, 0.85, 0.12), AssetKit.TRUNK,
			AssetKit.shade_by_facing(AssetKit.TRUNK, AssetKit.TRUNK, AssetKit.TRUNK_DARK))
	AssetKit.add_part(root, "Post", post.commit(mat))

	var cap := AssetKit.Builder.new()
	AssetKit.add_box(cap, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.875, 0.0)), Vector3(0.15, 0.05, 0.15), cap_swatch)
	AssetKit.add_part(root, "Cap", cap.commit(mat))

	var plate_path: String = "%s/yardage_%d.png" % [PLATE_TEXTURE_DIR, distance]
	var image: Image = Image.load_from_file(AssetKit.to_global(plate_path))
	if image == null:
		push_error("props: cannot load yardage plate %s (run tools/assets/make_yardage_plates.py)" % plate_path)
		root.free()
		return {}
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_texture = ImageTexture.create_from_image(image)
	plate_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	plate_mat.roughness = 0.9
	plate_mat.metallic = 0.0
	AssetKit.add_part(root, "Plate", _plate_mesh(plate_mat))
	return _export(root, out_dir, {"visual_only": true})


## Plate 0.36 x 0.22 m, UV 0..1 across the whole face. The front faces -Z (spec) and is read by a viewer
## looking along +Z with image left at +X. A mirrored back face at +Z (image left at -X) keeps the number
## legible from the other side too, e.g. from a preview or a camera on the far side of the post.
static func _plate_mesh(material: StandardMaterial3D) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	# Front (normal -Z), z just in front of the post.
	var zf: float = -0.065
	var f_tl := Vector3(0.18, 0.79, zf)
	var f_tr := Vector3(-0.18, 0.79, zf)
	var f_br := Vector3(-0.18, 0.57, zf)
	var f_bl := Vector3(0.18, 0.57, zf)
	_plate_tri(st, f_tl, f_br, f_bl, Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	_plate_tri(st, f_tl, f_tr, f_br, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector3(0.0, 0.0, -1.0))
	# Back (normal +Z), z just behind the post.
	var zb: float = 0.065
	var b_tl := Vector3(-0.18, 0.79, zb)
	var b_tr := Vector3(0.18, 0.79, zb)
	var b_br := Vector3(0.18, 0.57, zb)
	var b_bl := Vector3(-0.18, 0.57, zb)
	_plate_tri(st, b_tl, b_br, b_bl, Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), Vector3(0.0, 0.0, 1.0))
	_plate_tri(st, b_tl, b_tr, b_br, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector3(0.0, 0.0, 1.0))
	return st.commit()


## Adds one triangle given in the stored order (the kit's winding, reversed from the outward loop).
static func _plate_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, normal: Vector3) -> void:
	_plate_vertex(st, a, normal, uva)
	_plate_vertex(st, b, normal, uvb)
	_plate_vertex(st, c, normal, uvc)


static func _plate_vertex(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)
