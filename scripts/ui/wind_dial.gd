class_name WindDial
extends Control
## Compass dial with a wind arrow. The arrow points where the wind blows, relative to the aim line.

var _toward_target := 0.0
var _toward_right := 0.0
var _calm := true
var _strong_headwind := false

func _init() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_wind(toward_target: float, toward_right: float, calm: bool, strong_headwind: bool) -> void:
	if is_equal_approx(toward_target, _toward_target) and is_equal_approx(toward_right, _toward_right) and calm == _calm and strong_headwind == _strong_headwind:
		return
	_toward_target = toward_target
	_toward_right = toward_right
	_calm = calm
	_strong_headwind = strong_headwind
	queue_redraw()

func _draw() -> void:
	var center := Vector2(32, 32)
	draw_circle(center, 29.0, HudPalette.WELL)
	draw_arc(center, 29.0, 0.0, TAU, 48, HudPalette.FLAG if _strong_headwind else HudPalette.KEY_EDGE, 2.5 if _strong_headwind else 1.5, true)
	draw_rect(Rect2(31, 3, 2, 7), HudPalette.MUTED)
	draw_rect(Rect2(31, 54, 2, 7), HudPalette.KEY_EDGE)
	draw_rect(Rect2(3, 31, 7, 2), HudPalette.KEY_EDGE)
	draw_rect(Rect2(54, 31, 7, 2), HudPalette.KEY_EDGE)
	if _calm:
		draw_circle(center, 5.0, HudPalette.MUTED)
		return
	var angle := atan2(_toward_right, _toward_target)  # 0 = straight up
	draw_set_transform(center, angle)
	var half := 3.5 if _strong_headwind else 2.5
	var head := 13.0 if _strong_headwind else 11.0
	draw_rect(Rect2(-half, -12, half * 2.0, 30), HudPalette.LIVE)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -26 if _strong_headwind else -24), Vector2(head, -8), Vector2(-head, -8)]), HudPalette.LIVE)
	draw_set_transform(Vector2.ZERO)
