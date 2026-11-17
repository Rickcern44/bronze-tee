class_name PuttPreview
extends Node3D
## Putt preview on the green: the predicted path as dots that bunch up as the ball slows, a dashed aim line,
## and a stop ring labelled with feet past or short of the cup (or a ring on the cup if it drops).

const LIFT := 0.04
const DASH := 0.35
const GAP := 0.25
const AIM_LINE_WIDTH := 0.04
const STOP_RING_RADIUS := 0.2
const CUP_RING_RADIUS := 0.2
const FEET_PER_METER := 3.28084

## Callable(x: float, z: float) -> float
var ground_height := Callable()

var _builder := FxMeshBuilder.new()
var _mesh := ArrayMesh.new()
var _shapes: MeshInstance3D
var _dots: DotField
var _stop_chip: WorldChip
var _aim_chip: WorldChip

func _init() -> void:
	visible = false
	top_level = true
	_shapes = MeshInstance3D.new()
	_shapes.mesh = _mesh
	_shapes.material_override = FxMeshBuilder.make_material()
	_shapes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shapes)
	_dots = DotField.new()
	add_child(_dots)
	_stop_chip = WorldChip.new()
	add_child(_stop_chip)
	_aim_chip = WorldChip.new()
	add_child(_aim_chip)

func _ground(position: Vector3) -> float:
	return float(ground_height.call(position.x, position.z)) if ground_height.is_valid() else position.y

func _lifted(position: Vector3) -> Vector3:
	return Vector3(position.x, _ground(position) + LIFT, position.z)

## `path` is the sampled roll (world positions, evenly spaced in time); `past_cup_m` is signed.
func show_putt(start: Vector3, aim_degrees: float, path: PackedVector3Array, end: Vector3, cup: Vector3, holed: bool, past_cup_m: float) -> void:
	_builder.clear()
	# Aim line: dashes from the ball to just beyond the cup.
	var heading := deg_to_rad(aim_degrees)
	var direction := Vector3(sin(heading), 0.0, -cos(heading))
	var length := Vector2(cup.x - start.x, cup.z - start.z).length() + 0.6
	var aim_color := HudPalette.BRONZE_LABEL
	aim_color.a = 0.8
	var at := 0.0
	while at < length:
		var from := start + direction * at
		var to := start + direction * minf(at + DASH, length)
		_builder.segment(_lifted(from), _lifted(to), AIM_LINE_WIDTH, aim_color)
		at += DASH + GAP
	# Stop ring, or a ring on the cup if the putt drops.
	if holed:
		_builder.ring(_lifted(cup), CUP_RING_RADIUS, 0.04, HudPalette.CHALK, Basis.IDENTITY, 40)
		_stop_chip.set_chip("DROPS", HudPalette.CHALK, HudPalette.INK)
		_stop_chip.global_position = _lifted(cup) + Vector3.UP * 0.45
	else:
		var fill := HudPalette.LIVE
		fill.a = 0.2
		var stop := _lifted(end)
		_builder.disc(stop, STOP_RING_RADIUS, fill)
		_builder.ring(stop, STOP_RING_RADIUS, 0.035, HudPalette.LIVE, Basis.IDENTITY, 40)
		var feet := absf(past_cup_m) * FEET_PER_METER
		_stop_chip.set_chip("STOPS %.1f FT %s" % [feet, "PAST" if past_cup_m >= 0.0 else "SHORT"], HudPalette.LIVE, HudPalette.INK)
		_stop_chip.global_position = stop + Vector3.UP * 0.45
	_builder.commit(_mesh)
	var aim_end := start + direction * length
	_aim_chip.set_chip("AIM " + HudFormat.signed(aim_degrees, 2, "°"), HudPalette.INK, HudPalette.BRONZE_LABEL, HudPalette.BRONZE_LABEL)
	_aim_chip.global_position = _lifted(aim_end) + Vector3.UP * 0.3
	# Pace dots: white at the ball through live yellow to orange at the stop.
	var dots := PackedVector3Array()
	var colors := PackedColorArray()
	var count := path.size()
	for i in range(1, count):
		var t := float(i) / float(maxi(count - 1, 1))
		var color := HudPalette.TRAIL_HEAD.lerp(HudPalette.TRAIL_BODY, clampf(t / 0.55, 0.0, 1.0))
		if t > 0.55:
			color = HudPalette.TRAIL_BODY.lerp(HudPalette.PACE_END, (t - 0.55) / 0.45)
		dots.append(_lifted(path[i]) + Vector3.UP * 0.01)
		colors.append(color)
	_dots.set_dots(dots, colors, 3.0)
	visible = true

func hide_preview() -> void:
	visible = false
	_dots.clear()
