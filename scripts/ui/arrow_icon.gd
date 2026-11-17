class_name ArrowIcon
extends Control
## An 18 px arrow glyph in live yellow, pointing up, down, left or right.

enum Direction { UP, DOWN, LEFT, RIGHT }

var _direction := Direction.UP

func _init() -> void:
	custom_minimum_size = Vector2(18, 18)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_direction(direction: Direction) -> void:
	if direction == _direction:
		return
	_direction = direction
	queue_redraw()

func _draw() -> void:
	# Drawn pointing up, then rotated about the centre.
	draw_set_transform(Vector2(9, 9), [0.0, PI, -PI / 2.0, PI / 2.0][_direction])
	var points := PackedVector2Array([Vector2(0, 6), Vector2(0, -6)])
	draw_polyline(points, HudPalette.LIVE, 2.2, true)
	draw_polyline(PackedVector2Array([Vector2(-5, -1), Vector2(0, -6), Vector2(5, -1)]), HudPalette.LIVE, 2.2, true)
	draw_set_transform(Vector2.ZERO)
