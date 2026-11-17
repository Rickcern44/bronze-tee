class_name SegmentedControl
extends Control
## Segmented selector, e.g. the stimp speed 8 / 10 / 12. The selected segment is chalk.

var _options := PackedStringArray()
var _selected := 0

func _init() -> void:
	custom_minimum_size = Vector2(0, 32)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_options(options: PackedStringArray, selected: int) -> void:
	if options == _options and selected == _selected:
		return
	_options = options
	_selected = selected
	queue_redraw()

func _draw() -> void:
	draw_style_box(HudDraw.box(HudPalette.WELL, 6), Rect2(Vector2.ZERO, size))
	if _options.is_empty():
		return
	var gap := 3.0
	var width := (size.x - gap * (_options.size() + 1)) / _options.size()
	for i in range(_options.size()):
		var rect := Rect2(gap + i * (width + gap), gap, width, size.y - gap * 2.0)
		var on := i == _selected
		if on:
			draw_style_box(HudDraw.box(HudPalette.CHALK, 4), rect)
		HudDraw.text_centered(self, _options[i], HudFonts.condensed(700 if on else 600), HudTheme.FS_VALUE, rect, HudPalette.INK if on else HudPalette.MUTED)
