class_name LieIcon
extends Control
## A golf ball sitting on the current lie: tee, fairway, rough, bunker or green.

const DIMPLES := [Vector2(19, 20), Vector2(28, 17), Vector2(35, 22), Vector2(18, 29), Vector2(27, 27), Vector2(35, 31), Vector2(23, 36)]

var _lie := "Tee"

func _init() -> void:
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_lie(lie: String) -> void:
	if lie == _lie:
		return
	_lie = lie
	queue_redraw()

func _draw() -> void:
	var drop := 2.0 if _lie == "Rough" or _lie == "Bunker" else 0.0
	match _lie:
		"Fairway", "FirstCut": _patch(HudPalette.LIE_FAIRWAY)
		"Green": _patch(HudPalette.LIE_GREEN)
		"Tee": _patch(HudPalette.LIE_TEE)
	draw_circle(Vector2(28, 27 + drop), 19.0, HudPalette.BALL_EDGE)
	draw_circle(Vector2(26, 25 + drop), 17.0, HudPalette.BALL_FACE)
	for dimple in DIMPLES:
		draw_circle(dimple + Vector2(0, drop), 1.6, HudPalette.BALL_DIMPLE)
	if _lie == "Rough":
		var blades := PackedVector2Array([Vector2(3, 54), Vector2(8, 36), Vector2(12, 54), Vector2(17, 32), Vector2(22, 54), Vector2(28, 34), Vector2(33, 54), Vector2(38, 31), Vector2(43, 54), Vector2(48, 36), Vector2(53, 54)])
		draw_colored_polygon(blades, HudPalette.LIE_ROUGH)
	elif _lie == "Bunker":
		var dome := PackedVector2Array([Vector2(2, 54)])
		for i in range(1, 13):
			var t := i / 12.0
			dome.append(Vector2(2, 54) * pow(1 - t, 2) + Vector2(14, 38) * 2 * t * (1 - t) + Vector2(28, 42) * t * t)
		for i in range(1, 13):
			var t := i / 12.0
			dome.append(Vector2(28, 42) * pow(1 - t, 2) + Vector2(42, 46) * 2 * t * (1 - t) + Vector2(54, 54) * t * t)
		draw_colored_polygon(dome, HudPalette.LIE_BUNKER)
		for speck in [Vector2(12, 49), Vector2(30, 48), Vector2(44, 50)]:
			draw_circle(speck, 1.2, HudPalette.SAND_SPECK)

func _patch(color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32):
		var angle := TAU * i / 32.0
		points.append(Vector2(28 + cos(angle) * 25.0, 48 + sin(angle) * 6.0))
	draw_colored_polygon(points, color)
