class_name LandingMarker
extends Node3D
## Predicted landing for full shots: a flat double ring, a thin beacon, a distance chip and a dotted arc.
## Solid yellow = clean landing, dashed red with a cross = tree, dotted chalk = water.

enum Kind { CLEAN, TREE, WATER }

const RING_RADIUS := 1.3
const BEACON_HEIGHT := 4.0
const LIFT := 0.14

## Callable(x: float, z: float) -> float, used to tilt the ring onto the turf.
var ground_height := Callable()

var _meshes: Array[ArrayMesh] = []
var _ring: MeshInstance3D
var _beacon: MeshInstance3D
var _beacon_material: StandardMaterial3D
var _chip: WorldChip
var _arc: DotField

func _init() -> void:
	visible = false
	for kind in Kind.values():
		var mesh := ArrayMesh.new()
		_build_ring_mesh(kind, mesh)
		_meshes.append(mesh)
	_ring = MeshInstance3D.new()
	_ring.material_override = FxMeshBuilder.make_material()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_beacon = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, BEACON_HEIGHT, 0.06)
	_beacon.mesh = box
	_beacon.position.y = BEACON_HEIGHT * 0.5
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon.material_override = _beacon_material
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	_chip = WorldChip.new()
	_chip.position.y = BEACON_HEIGHT + 0.5
	add_child(_chip)
	_arc = DotField.new()
	add_child(_arc)

static func _build_ring_mesh(kind: int, mesh: ArrayMesh) -> void:
	var builder := FxMeshBuilder.new()
	var color: Color = [HudPalette.LIVE, HudPalette.FLAG, HudPalette.CHALK][kind]
	var fill := color
	fill.a = 0.18
	match kind:
		Kind.CLEAN:
			builder.disc(Vector3.ZERO, RING_RADIUS, fill)
			builder.ring(Vector3.ZERO, RING_RADIUS, 0.1, color)
			builder.ring(Vector3.ZERO, RING_RADIUS * 0.42, 0.05, color)
			builder.disc(Vector3.ZERO, 0.07, HudPalette.TRAIL_HEAD, Basis.IDENTITY, 12)
		Kind.TREE:
			builder.ring(Vector3.ZERO, RING_RADIUS, 0.1, color, Basis.IDENTITY, 72, 28.0, 17.0)
			var cross := 0.35
			builder.segment(Vector3(-cross, 0, -cross), Vector3(cross, 0, cross), 0.09, HudPalette.CHALK)
			builder.segment(Vector3(-cross, 0, cross), Vector3(cross, 0, -cross), 0.09, HudPalette.CHALK)
		Kind.WATER:
			builder.ring(Vector3.ZERO, RING_RADIUS, 0.1, color, Basis.IDENTITY, 120, 5.0, 15.0)
			builder.ring(Vector3.ZERO, RING_RADIUS * 0.42, 0.05, color)
	builder.commit(mesh)

## `path` is the sampled flight (world positions); `distance_m` is the carry shown on the chip.
func show_landing(position: Vector3, path: PackedVector3Array, kind: Kind, distance_m: float) -> void:
	var yards := roundi(distance_m * 1.0936133)
	var ground := _ground(position)
	global_position = Vector3(position.x, ground + LIFT, position.z)
	global_basis = _ground_basis(position)
	_ring.mesh = _meshes[kind]
	var color: Color = [HudPalette.LIVE, HudPalette.FLAG, HudPalette.CHALK][kind]
	_beacon_material.albedo_color = color
	match kind:
		Kind.CLEAN: _chip.set_chip("%d YD" % yards, HudPalette.LIVE, HudPalette.INK)
		Kind.TREE: _chip.set_chip("TREE \u00b7 %d" % yards, HudPalette.FLAG, HudPalette.INK)
		Kind.WATER: _chip.set_chip("WATER \u00b7 +1", HudPalette.CHALK, HudPalette.INK)
	var dots := PackedVector3Array()
	var colors := PackedColorArray()
	var arc_color := HudPalette.TRAIL_HEAD
	arc_color.a = 0.6
	# Skip the last sample, which sits on the ring itself.
	for i in range(maxi(path.size() - 1, 0)):
		dots.append(path[i])
		colors.append(arc_color)
	_arc.set_dots(dots, colors, 2.5)
	visible = true

func hide_marker() -> void:
	visible = false
	_arc.clear()

func _ground(position: Vector3) -> float:
	return float(ground_height.call(position.x, position.z)) if ground_height.is_valid() else position.y

func _ground_basis(position: Vector3) -> Basis:
	if not ground_height.is_valid():
		return Basis.IDENTITY
	var dx := (_ground(position + Vector3(0.5, 0, 0)) - _ground(position - Vector3(0.5, 0, 0)))
	var dz := (_ground(position + Vector3(0, 0, 0.5)) - _ground(position - Vector3(0, 0, 0.5)))
	var normal := Vector3(-dx, 1.0, -dz).normalized()
	var right := Vector3.RIGHT.slide(normal).normalized()
	return Basis(right, normal, right.cross(normal))
