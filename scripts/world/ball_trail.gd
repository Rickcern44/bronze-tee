class_name BallTrail
extends Node3D
## The ball trail: a camera-facing ribbon that fades and thins with age (white head, live body, bronze tail),
## a ground shadow track, a ring at each bounce, and dots while the ball rolls or is putted.
## One ArrayMesh and one DotField are reused for the whole life of the node.

enum Kind { AIR, ROLL }

const MAX_POINTS := 600
const AIR_INTERVAL := 0.05
const ROLL_INTERVAL := 0.12
const HEAD_WIDTH := 0.30
const FADE_SECONDS := 5.0
const REST_ALPHA := 0.0
const REST_BLEND_SECONDS := 0.6
const GROUND_LIFT := 0.12
const BOUNCE_WIDTH_FACTOR := 0.6

## Sampled positions (ribbon and roll dots), oldest first.
var points: Array[Vector3] = []
## Callable(x: float, z: float) -> float used to lay effects on the turf.
var ground_height := Callable()

var _times := PackedFloat32Array()
var _kinds := PackedInt32Array()
var _breaks := PackedInt32Array()
var _widths := PackedFloat32Array()
var _marks: Array[Dictionary] = []  # {type, position, time, radius}
var _clock := 0.0
var _sample_clock := 0.0
var _head := Vector3.ZERO
var _airborne := false
var _bounced := false
var _thin := 1.0
var _water := false
var _last_vy := 0.0
var _resting := false
var _rest_blend := 0.0
var _dirty := false
var _last_camera := Vector3(INF, INF, INF)
var _builder := FxMeshBuilder.new()
var _mesh := ArrayMesh.new()
var _ribbon_instance: MeshInstance3D
var _dots: DotField

func _init() -> void:
	top_level = true
	_ribbon_instance = MeshInstance3D.new()
	_ribbon_instance.mesh = _mesh
	_ribbon_instance.material_override = FxMeshBuilder.make_material()
	_ribbon_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon_instance)
	_dots = DotField.new()
	add_child(_dots)

func clear() -> void:
	points.clear()
	_times.clear()
	_kinds.clear()
	_breaks.clear()
	_widths.clear()
	_marks.clear()
	_clock = 0.0
	_sample_clock = 0.0
	_airborne = false
	_bounced = false
	_thin = 1.0
	_water = false
	_last_vy = 0.0
	_resting = false
	_rest_blend = 0.0
	_mesh.clear_surfaces()
	_dots.clear()
	_dirty = false

## Call once per physics tick while the ball is moving.
func track(position: Vector3, velocity: Vector3, airborne: bool, has_landed: bool, delta: float) -> void:
	_clock += delta
	_head = position
	var was_airborne := _airborne
	_airborne = airborne
	_resting = false
	_rest_blend = 0.0
	if airborne and has_landed and _last_vy < 0.0 and velocity.y > 0.0:
		_add_bounce(position)
	_last_vy = velocity.y
	_sample_clock += delta
	var interval := AIR_INTERVAL if airborne else ROLL_INTERVAL
	if points.is_empty() or _sample_clock >= interval or was_airborne != airborne:
		_sample_clock = 0.0
		_add_point(position, Kind.AIR if airborne else Kind.ROLL, false)
	_dirty = true

## The ball has stopped: dim the trail to its resting alpha.
func set_resting() -> void:
	if _resting:
		return
	_resting = true
	_airborne = false
	_dirty = true

func mark_tree_hit(position: Vector3) -> void:
	_marks.append({"type": "burst", "position": position, "time": _clock, "radius": 0.0})
	_add_point(position, Kind.AIR, true)
	_thin = BOUNCE_WIDTH_FACTOR
	_dirty = true

func mark_water(position: Vector3) -> void:
	_water = true
	_marks.append({"type": "ripple", "position": position, "time": _clock, "radius": 1.4})
	_marks.append({"type": "ripple", "position": position, "time": _clock, "radius": 0.65})
	_airborne = false
	_dirty = true

func _add_bounce(position: Vector3) -> void:
	_add_point(position, Kind.AIR, false)
	_marks.append({"type": "bounce", "position": position, "time": _clock, "radius": 0.5 if _bounced else 1.1})
	_bounced = true
	_thin = BOUNCE_WIDTH_FACTOR

func _add_point(position: Vector3, kind: Kind, break_strand: bool) -> void:
	points.append(position)
	_times.append(_clock)
	_kinds.append(kind)
	_breaks.append(1 if break_strand else 0)
	_widths.append(_thin)
	if points.size() > MAX_POINTS:
		points.remove_at(0)
		_times.remove_at(0)
		_kinds.remove_at(0)
		_breaks.remove_at(0)
		_widths.remove_at(0)

func _process(delta: float) -> void:
	if _resting and _rest_blend < 1.0:
		_rest_blend = minf(1.0, _rest_blend + delta / REST_BLEND_SECONDS)
		_dirty = true
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null and not camera.global_position.is_equal_approx(_last_camera):
		_last_camera = camera.global_position
		_dirty = not points.is_empty() or not _marks.is_empty() or _dirty
	if _dirty:
		_rebuild(camera)

func _ground(position: Vector3) -> float:
	if ground_height.is_valid():
		return float(ground_height.call(position.x, position.z)) + GROUND_LIFT
	return position.y

func _strength(time: float) -> float:
	return clampf(1.0 - (_clock - time) / FADE_SECONDS, 0.0, 1.0)

## Fade effects close to the camera or directly between the camera and the ball.
static func view_visibility(position: Vector3, camera_position: Vector3, ball_position: Vector3) -> float:
	var near_camera := smoothstep(1.5, 5.0, position.distance_to(camera_position))
	var ray := ball_position - camera_position
	var length_squared := ray.length_squared()
	if length_squared < 0.0001: return near_camera
	var along := (position - camera_position).dot(ray) / length_squared
	if along <= 0.0 or along >= 1.05: return near_camera
	var separation := position.distance_to(camera_position + ray * clampf(along, 0.0, 1.0))
	return near_camera * lerpf(0.12, 1.0, smoothstep(0.3, 1.25, separation))

static func color_for(strength: float) -> Color:
	if strength > 0.8:
		var color := HudPalette.TRAIL_HEAD.lerp(HudPalette.TRAIL_BODY, (1.0 - strength) / 0.2)
		color.a = lerpf(1.0, 0.95, (1.0 - strength) / 0.2)
		return color
	if strength > 0.3:
		var color := HudPalette.TRAIL_BODY.lerp(HudPalette.TRAIL_MID, (0.8 - strength) / 0.5)
		color.a = lerpf(0.95, 0.55, (0.8 - strength) / 0.5)
		return color
	var color := HudPalette.TRAIL_MID.lerp(HudPalette.TRAIL_TAIL, (0.3 - strength) / 0.3)
	color.a = lerpf(0.55, 0.0, (0.3 - strength) / 0.3)
	return color

func _rebuild(camera: Camera3D) -> void:
	_dirty = false
	_builder.clear()
	var dim := lerpf(1.0, REST_ALPHA, _rest_blend)
	var view: Variant = camera.global_position if camera != null else Vector3(0, 10, 10)
	var strand := PackedVector3Array()
	var half_widths := PackedFloat32Array()
	var colors := PackedColorArray()
	var dot_positions := PackedVector3Array()
	var dot_colors := PackedColorArray()
	for i in range(points.size()):
		var strength := _strength(_times[i])
		var view_fade := view_visibility(points[i], view, _head) if camera != null else 1.0
		if _kinds[i] == Kind.ROLL:
			var dot_color := HudPalette.BRONZE
			dot_color.a = lerpf(0.4, 1.0, strength) * dim * view_fade
			dot_positions.append(points[i] + Vector3(0, GROUND_LIFT * 0.5, 0))
			dot_colors.append(dot_color)
			continue
		if _breaks[i] == 1 and not strand.is_empty():
			_flush_strand(strand, half_widths, colors, view)
			strand = PackedVector3Array()
			half_widths = PackedFloat32Array()
			colors = PackedColorArray()
		strand.append(points[i])
		half_widths.append(HEAD_WIDTH * 0.5 * _widths[i] * strength)
		var color := color_for(strength)
		color.a *= dim * view_fade
		colors.append(color)
	if _airborne and not points.is_empty():
		strand.append(_head)
		half_widths.append(HEAD_WIDTH * 0.5 * _thin)
		var head_color := color_for(1.0)
		head_color.a *= view_visibility(_head, view, _head) if camera != null else 1.0
		colors.append(head_color)
	_flush_strand(strand, half_widths, colors, view)
	_dots.set_dots(dot_positions, dot_colors, 3.5)
	_build_marks(camera, dim)
	if _airborne:
		_build_head(camera)
	_builder.commit(_mesh)

func _flush_strand(strand: PackedVector3Array, half_widths: PackedFloat32Array, colors: PackedColorArray, view: Variant) -> void:
	if strand.size() < 2:
		return
	if _water:
		for i in range(colors.size()):
			var u := float(i) / float(colors.size() - 1)
			var tinted := colors[i].lerp(HudPalette.FLAG, pow(u, 1.5))
			tinted.a = colors[i].a
			colors[i] = tinted
	var shadow := PackedVector3Array()
	var shadow_widths := PackedFloat32Array()
	var shadow_colors := PackedColorArray()
	for i in range(strand.size()):
		shadow.append(Vector3(strand[i].x, _ground(strand[i]), strand[i].z))
		shadow_widths.append(0.08)
		var shade := HudPalette.GROUND_SHADOW
		shade.a = 0.4 * colors[i].a
		shadow_colors.append(shade)
	_builder.ribbon(shadow, shadow_widths, shadow_colors)
	_builder.ribbon(strand, half_widths, colors, view)

func _build_head(camera: Camera3D) -> void:
	# Avoid a large camera-facing halo or stem covering the ball in close views.
	if camera != null and camera.global_position.distance_to(_head) < 12.0: return
	var per_pixel := FxView.world_per_pixel(camera, _head)
	var ground := Vector3(_head.x, _ground(_head), _head.z)
	var stem := HudPalette.TRAIL_HEAD
	stem.a = 0.4
	if _head.y - ground.y > 0.5:
		_builder.segment(_head, ground, per_pixel * 1.5, stem, camera.global_position if camera != null else Vector3(0, 10, 10))
	var shade := HudPalette.GROUND_SHADOW
	shade.a = 0.55
	_builder.disc(ground, maxf(0.12, per_pixel * 6.0), shade)
	if camera != null:
		var facing := Basis(camera.global_basis.x, camera.global_basis.z, -camera.global_basis.y)
		var halo := HudPalette.TRAIL_HEAD
		halo.a = 0.25
		var radius := maxf(HEAD_WIDTH * 0.5, per_pixel * 5.0)
		_builder.disc(_head, radius * 1.9, halo, facing)
		_builder.disc(_head, radius, HudPalette.TRAIL_HEAD, facing)

func _build_marks(camera: Camera3D, dim: float) -> void:
	var up := camera.global_basis.y if camera != null else Vector3.UP
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	for mark in _marks:
		var position: Vector3 = mark.position
		var view_fade := view_visibility(position, camera.global_position, _head) if camera != null else 1.0
		var ground := Vector3(position.x, _ground(position), position.z)
		match mark.type:
			"bounce":
				var color := HudPalette.LIVE
				color.a = lerpf(0.5, 1.0, _strength(mark.time)) * dim * view_fade
				var radius: float = mark.radius
				_builder.ring(ground, radius, 0.09 if radius > 0.8 else 0.06, color)
			"ripple":
				var color := HudPalette.WATER
				color.a *= dim * view_fade
				_builder.ring(ground, mark.radius, 0.07, color)
			"burst":
				var size := maxf(0.35, FxView.world_per_pixel(camera, position) * 12.0)
				var view_position: Variant = camera.global_position if camera != null else Vector3(0, 10, 10)
				var line_width := size * 0.12
				for direction in [right, up, (right + up).normalized(), (right - up).normalized()]:
					var color := HudPalette.CHALK
					color.a *= dim * view_fade
					_builder.segment(position - direction * size, position + direction * size, line_width, color, view_position)
