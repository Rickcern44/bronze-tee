class_name GreenRead
extends Node3D
## Approximate downhill arrows and a marker for the previous putt's start.

const SPACING := 3.0
const LIFT := 0.055
var ground_height := Callable()
var ground_slope := Callable()
var cup := Vector3.ZERO
var radii := Vector2.ONE
var _last_key: Array = []
var _mesh := ArrayMesh.new()
var _builder := FxMeshBuilder.new()

func _init() -> void:
	top_level = true
	visible = false
	var shapes := MeshInstance3D.new()
	shapes.mesh = _mesh
	shapes.material_override = FxMeshBuilder.make_material()
	shapes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shapes)

func _point(position: Vector2) -> Vector3:
	return Vector3(position.x, float(ground_height.call(position.x, position.y)) + LIFT, position.y)

func show_read(ball: Vector3, previous_start: Vector3, show_previous: bool, show_slopes: bool) -> void:
	if not ground_height.is_valid() or not ground_slope.is_valid(): return
	var key := [ball, previous_start, show_previous, show_slopes, cup, radii]
	if key == _last_key:
		visible = true
		return
	_last_key = key
	_builder.clear()
	var green_color := Color(0.83, 0.95, 0.75, 0.60)
	for ix in range(-ceili(radii.x / SPACING), ceili(radii.x / SPACING) + 1):
		for iz in range(-ceili(radii.y / SPACING), ceili(radii.y / SPACING) + 1):
			if not show_slopes: continue
			var offset := Vector2(ix * SPACING, iz * SPACING)
			if Vector2(offset.x / radii.x, offset.y / radii.y).length() > 0.90: continue
			var center := Vector2(cup.x, cup.z) + offset
			if center.distance_to(Vector2(ball.x, ball.z)) < 1.0 or offset.length() < 0.8: continue
			var position := _point(center)
			var slope: Vector2 = ground_slope.call(position)
			if slope.length() < 0.001:
				_builder.disc(position, 0.06, green_color, Basis.IDENTITY, 8)
				continue
			var downhill := -slope.normalized()
			var length := lerpf(0.35, 1.0, clampf(slope.length() / 0.03, 0.0, 1.0))
			var tip := center + downhill * length * 0.5
			var tail := center - downhill * length * 0.5
			var side := Vector2(-downhill.y, downhill.x)
			_builder.segment(_point(tail), _point(tip), 0.045, green_color)
			_builder.segment(_point(tip), _point(tip - downhill * 0.24 + side * 0.14), 0.045, green_color)
			_builder.segment(_point(tip), _point(tip - downhill * 0.24 - side * 0.14), 0.045, green_color)
	if show_previous:
		var start := _point(Vector2(previous_start.x, previous_start.z))
		_builder.ring(start, 0.20, 0.04, Color(1.0, 0.75, 0.35, 0.85), Basis.IDENTITY, 32)
	_builder.commit(_mesh)
	visible = true
