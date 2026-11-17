class_name SwipeGauge
extends Control
## Swipe direction gauge: a track with a dead-zone band and a handle that moves left or right of centre.

var _degrees := 0.0
var _max_degrees := 12.0
var _dead_zone := 2.0
var _filled := false

func _init() -> void:
	custom_minimum_size = Vector2(60, 16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_gauge(degrees: float, max_degrees: float, dead_zone: float, filled: bool) -> void:
	if is_equal_approx(degrees, _degrees) and is_equal_approx(max_degrees, _max_degrees) and is_equal_approx(dead_zone, _dead_zone) and filled == _filled:
		return
	_degrees = degrees
	_max_degrees = max_degrees
	_dead_zone = dead_zone
	_filled = filled
	queue_redraw()

func _draw() -> void:
	var track := Rect2(0, 4, size.x, 8)
	draw_style_box(HudDraw.box(HudPalette.WELL, 4), track)
	var center_x := size.x * 0.5
	var half_dead := size.x * 0.5 * _dead_zone / _max_degrees
	draw_rect(Rect2(center_x - half_dead, track.position.y, half_dead * 2.0, track.size.y), HudPalette.LINE)
	var handle_x := center_x + size.x * 0.5 * clampf(_degrees / _max_degrees, -1.0, 1.0)
	if _filled and absf(handle_x - center_x) > 0.5:
		draw_rect(Rect2(minf(center_x, handle_x), track.position.y, absf(handle_x - center_x), track.size.y), HudPalette.BRONZE)
	draw_style_box(HudDraw.box(HudPalette.CHALK, 2), Rect2(handle_x - 2.0, 0, 4, 16))
