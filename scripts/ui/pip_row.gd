class_name PipRow
extends Control
## A row of small bars with one lit in live yellow.

var _count := 3
var _active := 0
var _pip_width := 17.0

func _init(count: int = 3, pip_width: float = 17.0) -> void:
	_count = count
	_pip_width = pip_width
	custom_minimum_size = Vector2(count * pip_width + (count - 1) * 3.0, 5)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_active(index: int) -> void:
	if index == _active:
		return
	_active = index
	queue_redraw()

func _draw() -> void:
	for i in range(_count):
		draw_style_box(HudDraw.box(HudPalette.LIVE if i == _active else HudPalette.LINE, 2), Rect2(i * (_pip_width + 3.0), 0, _pip_width, 5))
