class_name ScoreCell
extends Control
## One scorecard cell: "H2" over a dot (unplayed or in progress) or a circled/boxed score.

enum Mode { TO_PLAY, SCORED }

var _hole_number := 1
var _mode := Mode.TO_PLAY
var _score := 0
var _par := 4
var _current := false

func _init() -> void:
	custom_minimum_size = Vector2(42, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_cell(hole_number: int, mode: Mode, score: int, par: int, current: bool) -> void:
	if hole_number == _hole_number and mode == _mode and score == _score and par == _par and current == _current:
		return
	_hole_number = hole_number
	_mode = mode
	_score = score
	_par = par
	_current = current
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _current:
		draw_style_box(HudDraw.box(Color(0, 0, 0, 0), 6, HudPalette.BRONZE, 2), rect)
	else:
		draw_style_box(HudDraw.box(HudPalette.WELL, 6), rect)
	var small := HudFonts.condensed(600)
	var big := HudFonts.condensed(700)
	HudDraw.text_centered(self, "H%d" % _hole_number, small, HudTheme.FS_MICRO, Rect2(0, 6, size.x, 12), HudPalette.BRONZE_LABEL if _current else HudPalette.MUTED)
	var body := Rect2(0, 20, size.x, 20)
	if _mode != Mode.SCORED:
		HudDraw.text_centered(self, "·", big, 18, body, HudPalette.CHALK if _current else HudPalette.MUTED)
		return
	var relative := _score - _par
	var color := HudPalette.CHALK
	var center := body.get_center()
	if _score == 1 or relative < 0:
		color = HudPalette.LIVE
		draw_arc(center, 10.0, 0.0, TAU, 24, color, 2.0, true)
		if relative <= -2:
			draw_arc(center, 13.0, 0.0, TAU, 28, color, 1.5, true)
	elif relative > 0:
		color = HudPalette.MUTED
		draw_rect(Rect2(center - Vector2(10, 10), Vector2(20, 20)), color, false, 2.0)
		if relative >= 2:
			draw_rect(Rect2(center - Vector2(13, 13), Vector2(26, 26)), color, false, 1.5)
	HudDraw.text_centered(self, str(_score), big, 16 if relative != 0 else 18, body, color)
