class_name PowerBar
extends Control
## The swing power bar: quarter ticks, a fill whose colour shows the state, and an optional suggested-power notch.

enum Style { EMPTY, TOO_SHORT, BACKSWING, LOCKED, LAST }

const BAR_HEIGHT := 18.0
const TAG_HEIGHT := 16.0

var _fraction := 0.0
var _style := Style.EMPTY
var _suggested := -1.0
var _reserve_tag := false

func _init() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_bar(fraction: float, style: Style, suggested: float, reserve_tag: bool) -> void:
	if is_equal_approx(fraction, _fraction) and style == _style and is_equal_approx(suggested, _suggested) and reserve_tag == _reserve_tag:
		return
	_fraction = fraction
	_style = style
	_suggested = suggested
	if reserve_tag != _reserve_tag:
		_reserve_tag = reserve_tag
		custom_minimum_size.y = BAR_HEIGHT + (TAG_HEIGHT if reserve_tag else 0.0)
	queue_redraw()

func _draw() -> void:
	var bar := Rect2(0, size.y - BAR_HEIGHT, size.x, BAR_HEIGHT)
	var border := HudPalette.LIVE if _style == Style.LOCKED else HudPalette.LINE
	draw_style_box(HudDraw.box(HudPalette.WELL, 5, border, 1), bar)
	if _style == Style.TOO_SHORT:
		HudDraw.dashed_rect(self, bar.grow(-0.5), HudPalette.MUTED)
	var inner := bar.grow(-1.0)
	var fill_width := inner.size.x * clampf(_fraction, 0.0, 1.0)
	if fill_width > 0.5:
		var fill_color := HudPalette.BRONZE
		match _style:
			Style.LOCKED: fill_color = HudPalette.LIVE
			Style.LAST: fill_color = HudPalette.BRONZE_DIM
		var full := fill_width >= inner.size.x - 0.5
		var style := HudDraw.box(fill_color, 4)
		style.corner_radius_top_right = 4 if full else 0
		style.corner_radius_bottom_right = 4 if full else 0
		draw_style_box(style, Rect2(inner.position, Vector2(fill_width, inner.size.y)))
	for quarter in [0.25, 0.5, 0.75]:
		var x: float = inner.position.x + inner.size.x * quarter
		var covered: bool = x <= inner.position.x + fill_width
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), HudPalette.INK if covered else HudPalette.KEY_EDGE, 1.0)
	if _suggested >= 0.0:
		var notch_x := inner.position.x + inner.size.x * clampf(_suggested, 0.0, 1.0)
		var label := "SUGGESTED %d%%" % roundi(_suggested * 100.0)
		HudDraw.text_centered(self, label, HudFonts.condensed(700, 1.0), HudTheme.FS_MICRO, Rect2(notch_x - 60, 0, 120, 12), HudPalette.CHALK)
		draw_rect(Rect2(notch_x - 2.5, bar.position.y - 2, 5, BAR_HEIGHT + 4), HudPalette.INK)
		draw_rect(Rect2(notch_x - 1.5, bar.position.y - 1, 3, BAR_HEIGHT + 2), HudPalette.CHALK)
