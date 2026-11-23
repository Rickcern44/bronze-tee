class_name HoleCard
extends PanelContainer
## Hole badge, course/par line, stroke counter, scorecard cells and the round chip.

var _badge_number: Label
var _par_line: Label
var _course: Label
var _strokes: Label
var _cells: Array[ScoreCell] = []
var _round_chip: RoundChip
var _cells_row: HBoxContainer
var _scorecard: VBoxContainer
var _section_rows: Array[HBoxContainer] = []
var _section_totals: Array[Label] = []
var _total_label: Label

func _init() -> void:
	theme_type_variation = HudTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := HudTheme.vbox(10)
	add_child(column)
	var top := HudTheme.hbox(12)
	column.add_child(top)
	var badge := HudTheme.panel(HudTheme.BADGE)
	badge.custom_minimum_size = Vector2(54, 54)
	top.add_child(badge)
	var badge_column := HudTheme.vbox(0)
	badge_column.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(badge_column)
	var hole_word := HudTheme.label("HOLE", HudTheme.NUM_BOLD, HudTheme.FS_MICRO, HudPalette.INK)
	hole_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_column.add_child(hole_word)
	_badge_number = HudTheme.label("1", HudTheme.NUM_BOLD, HudTheme.FS_BIG + 6, HudPalette.INK)
	_badge_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_number.add_theme_constant_override("line_spacing", -8)
	badge_column.add_child(_badge_number)
	var titles := HudTheme.vbox(5)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(titles)
	_course = HudTheme.label("ROYAL CREST", HudTheme.CAPS)
	titles.add_child(_course)
	_par_line = HudTheme.label("", HudTheme.NUM, 24)
	titles.add_child(_par_line)
	column.add_child(HudTheme.divider())
	var bottom := HudTheme.hbox(0)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(bottom)
	var stroke_box := HudTheme.vbox(2)
	stroke_box.custom_minimum_size.x = 48
	stroke_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stroke_box.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(stroke_box)
	stroke_box.add_child(HudTheme.label("STROKE", HudTheme.CAPS_MUTED))
	_strokes = HudTheme.label("0", HudTheme.NUM_BOLD, HudTheme.FS_BIG)
	stroke_box.add_child(_strokes)
	_scorecard = HudTheme.vbox(3)
	bottom.add_child(_scorecard)
	_cells_row = HudTheme.hbox(4)
	_scorecard.add_child(_cells_row)
	_round_chip = RoundChip.new()
	_cells_row.add_child(_round_chip)

func apply_state(state: HudState) -> void:
	var holes := state.hole_pars.size()
	var long_course := holes > 9
	if long_course and _section_rows.is_empty():
		for section in range(2):
			var row := HudTheme.hbox(2)
			_scorecard.add_child(row)
			var section_name := HudTheme.label("OUT" if section == 0 else "IN", HudTheme.CAPS_MUTED, HudTheme.FS_MICRO)
			section_name.custom_minimum_size.x = 27
			row.add_child(section_name)
			_section_rows.append(row)
	while _cells.size() < holes:
		var cell := ScoreCell.new()
		_cells.append(cell)
		if long_course:
			cell.custom_minimum_size.x = 27
			_section_rows[mini((_cells.size() - 1) / 9, 1)].add_child(cell)
		else:
			_cells_row.add_child(cell)
			_cells_row.move_child(cell, _cells.size() - 1)
	if long_course and _section_totals.is_empty():
		for row in _section_rows:
			var subtotal := HudTheme.label("0", HudTheme.NUM_BOLD, HudTheme.FS_MICRO, HudPalette.CHALK)
			subtotal.custom_minimum_size.x = 24
			subtotal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(subtotal)
			_section_totals.append(subtotal)
		_total_label = HudTheme.label("TOTAL  0", HudTheme.NUM_BOLD, HudTheme.FS_MICRO, HudPalette.BRONZE_LABEL)
		_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_scorecard.add_child(_total_label)
	if long_course:
		for i in range(_cells.size()):
			var row: HBoxContainer = _section_rows[mini(i / 9, 1)]
			if _cells[i].get_parent() != row:
				_cells_row.remove_child(_cells[i])
				_cells[i].custom_minimum_size.x = 27
				row.add_child(_cells[i])
	elif not _section_rows.is_empty():
		for cell in _cells:
			if cell.get_parent() != _cells_row:
				cell.get_parent().remove_child(cell)
				cell.custom_minimum_size.x = 42
				_cells_row.add_child(cell)
		_section_rows.clear()
		_section_totals.clear()
		_total_label.queue_free()
		_total_label = null
	_set_text(_badge_number, str(state.hole_index + 1))
	_set_text(_course, state.course_name.to_upper())
	var par := state.hole_pars[state.hole_index] if holes > state.hole_index else 4
	_set_text(_par_line, "PAR %d · %d YD · %s" % [par, roundi(state.hole_yards), state.tee_name])
	_set_text(_strokes, str(state.strokes))
	var total := 0
	var par_total := 0
	for i in range(holes):
		var played := i < state.hole_scores.size() and state.hole_scores[i] >= 0
		var score := state.hole_scores[i] if played else 0
		_cells[i].set_cell(i + 1, ScoreCell.Mode.SCORED if played else ScoreCell.Mode.TO_PLAY, score, state.hole_pars[i], i == state.hole_index)
		if played:
			total += score
			par_total += state.hole_pars[i]
	if long_course:
		for section in range(2):
			var subtotal := 0
			for i in range(section * 9, mini((section + 1) * 9, holes)):
				if i < state.hole_scores.size() and state.hole_scores[i] >= 0:
					subtotal += state.hole_scores[i]
			_section_totals[section].text = str(subtotal)
		_total_label.text = "TOTAL  %d" % total
	_round_chip.set_relative(total - par_total)

func badge_text() -> String:
	return _badge_number.text

func par_text() -> String:
	return _par_line.text

static func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
