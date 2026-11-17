class_name ToastIcon
extends Control
## A water drop used on alert toasts.

func _init() -> void:
	custom_minimum_size = Vector2(28, 28)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_circle(Vector2(14, 18), 8.0, HudPalette.WATER)
	draw_colored_polygon(PackedVector2Array([Vector2(14, 3), Vector2(21, 15), Vector2(7, 15)]), HudPalette.WATER)
