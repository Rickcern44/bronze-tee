class_name DotField
extends MultiMeshInstance3D
## Many round dots in one draw call. Dots face the camera and keep a constant on-screen size.
## The node ignores its parent's transform; positions are world positions.

const CAPACITY := 512

var _positions := PackedVector3Array()
var _colors := PackedColorArray()
var _pixel_radius := 3.0
var _last_camera := Vector3(INF, INF, INF)

static var _disc_mesh: ArrayMesh

func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _shared_disc()
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	set_process(false)

static func _shared_disc() -> ArrayMesh:
	if _disc_mesh != null:
		return _disc_mesh
	var vertices := PackedVector3Array()
	var segments := 12
	for i in range(segments):
		vertices.append(Vector3.ZERO)
		vertices.append(Vector3(cos(TAU * i / segments), sin(TAU * i / segments), 0))
		vertices.append(Vector3(cos(TAU * (i + 1) / segments), sin(TAU * (i + 1) / segments), 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	mesh.surface_set_material(0, material)
	_disc_mesh = mesh
	return mesh

func set_dots(positions: PackedVector3Array, colors: PackedColorArray, pixel_radius: float = 3.0) -> void:
	_positions = positions.slice(0, CAPACITY)
	_colors = colors.slice(0, CAPACITY)
	_pixel_radius = pixel_radius
	multimesh.visible_instance_count = _positions.size()
	_last_camera = Vector3(INF, INF, INF)
	set_process(not _positions.is_empty())
	_refresh()

func clear() -> void:
	set_dots(PackedVector3Array(), PackedColorArray())

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	if _positions.is_empty():
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var camera_position := camera.global_position if camera != null else Vector3.ZERO
	if camera_position.is_equal_approx(_last_camera):
		return
	_last_camera = camera_position
	for i in range(_positions.size()):
		var radius := FxView.world_per_pixel(camera, _positions[i]) * _pixel_radius
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * radius), _positions[i]))
		multimesh.set_instance_color(i, _colors[i])
