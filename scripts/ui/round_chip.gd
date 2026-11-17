class_name RoundChip
extends Control
## "ROUND E / -1 / +2" chip at the end of the scorecard: chalk when even, live when under, outlined when over.

var _relative := 0

func _init() -> void:
	custom_minimum_size = Vector2(52, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_relative(relative: int) -> void:
	if relative == _relative:
		return
	_relative = relative
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var text_color := HudPalette.INK
	if _relative < 0:
		draw_style_box(HudDraw.box(HudPalette.LIVE, 6), rect)
	elif _relative > 0:
		draw_style_box(HudDraw.box(HudPalette.WELL, 6, HudPalette.MUTED, 2), rect)
		text_color = HudPalette.CHALK
	else:
		draw_style_box(HudDraw.box(HudPalette.CHALK, 6), rect)
	HudDraw.text_centered(self, "ROUND", HudFonts.condensed(700, 0.9), HudTheme.FS_MICRO, Rect2(0, 6, size.x, 12), text_color)
	HudDraw.text_centered(self, HudFormat.relative_to_par(_relative), HudFonts.condensed(700), 18, Rect2(0, 20, size.x, 20), text_color)
