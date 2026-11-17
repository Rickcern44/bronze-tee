class_name FxMeshBuilder
extends RefCounted
## Accumulates coloured triangles (rings, ribbons, discs) and writes them into one reusable ArrayMesh.

var _vertices := PackedVector3Array()
var _colors := PackedColorArray()

static func make_material(no_depth_test: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = no_depth_test
	return material

func clear() -> void:
	_vertices.clear()
	_colors.clear()

func is_empty() -> bool:
	return _vertices.is_empty()

func triangle(a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color) -> void:
	_vertices.append(a)
	_vertices.append(b)
	_vertices.append(c)
	_colors.append(color_a)
	_colors.append(color_b)
	_colors.append(color_c)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color_ab: Color, color_cd: Color) -> void:
	triangle(a, b, c, color_ab, color_ab, color_cd)
	triangle(a, c, d, color_ab, color_cd, color_cd)

## A strip along `points`. Each point has its own half width and colour. When `view_position` is given the
## strip faces that viewpoint; otherwise it lies flat in the horizontal plane.
func ribbon(points: PackedVector3Array, half_widths: PackedFloat32Array, colors: PackedColorArray, view_position: Variant = null) -> void:
	var count := points.size()
	if count < 2:
		return
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var last_side := Vector3.RIGHT
	for i in range(count):
		var tangent := points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]
		var facing := Vector3.UP if view_position == null else (view_position as Vector3) - points[i]
		var side := tangent.cross(facing)
		if side.length_squared() < 0.0000001:
			side = last_side
		side = side.normalized()
		last_side = side
		left.append(points[i] - side * half_widths[i])
		right.append(points[i] + side * half_widths[i])
	for i in range(count - 1):
		quad(left[i], right[i], right[i + 1], left[i + 1], colors[i], colors[i + 1])

func segment(a: Vector3, b: Vector3, width: float, color: Color, view_position: Variant = null) -> void:
	ribbon(PackedVector3Array([a, b]), PackedFloat32Array([width * 0.5, width * 0.5]), PackedColorArray([color, color]), view_position)

## A flat ring in the plane of `basis` (its Y axis is the ring normal). Dashes are in degrees; gap 0 draws it solid.
func ring(center: Vector3, radius: float, width: float, color: Color, basis: Basis = Basis.IDENTITY, segments: int = 48, dash_degrees: float = 0.0, gap_degrees: float = 0.0) -> void:
	var inner := radius - width * 0.5
	var outer := radius + width * 0.5
	var step := TAU / segments
	for i in range(segments):
		if gap_degrees > 0.0:
			var middle := rad_to_deg((i + 0.5) * step)
			if fmod(middle, dash_degrees + gap_degrees) > dash_degrees:
				continue
		var a := i * step
		var b := (i + 1) * step
		var dir_a := basis * Vector3(cos(a), 0, sin(a))
		var dir_b := basis * Vector3(cos(b), 0, sin(b))
		quad(center + dir_a * inner, center + dir_a * outer, center + dir_b * outer, center + dir_b * inner, color, color)

func disc(center: Vector3, radius: float, color: Color, basis: Basis = Basis.IDENTITY, segments: int = 32) -> void:
	var step := TAU / segments
	for i in range(segments):
		var dir_a := basis * Vector3(cos(i * step), 0, sin(i * step))
		var dir_b := basis * Vector3(cos((i + 1) * step), 0, sin((i + 1) * step))
		triangle(center, center + dir_a * radius, center + dir_b * radius, color, color, color)

func commit(mesh: ArrayMesh) -> void:
	mesh.clear_surfaces()
	if _vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = _colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
