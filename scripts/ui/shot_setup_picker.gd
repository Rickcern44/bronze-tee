class_name ShotSetupPicker
extends PanelContainer
## Expanded shape/type/spin chips, shown for a moment after any of those change.

const SHOW_SECONDS := 1.5

var _rows: Array[Array] = []  # each: [Array[PanelContainer] chips]
var _remaining := 0.0
var _last: Array = []
var _context: Array = []

func _init() -> void:
	theme_type_variation = HudTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	var column := HudTheme.vbox(10)
	add_child(column)
	_add_row(column, "SHAPE", ClubCard.SHAPES, ["U", "I"])
	_add_row(column, "TYPE", ClubCard.TYPES, ["J", "K"])
	_add_row(column, "SPIN", ClubCard.SPINS, ["B"])

func _add_row(parent: Control, caption: String, names: Array, keys: Array) -> void:
	var row := HudTheme.hbox(6)
	parent.add_child(row)
	var cap := HudTheme.label(caption, HudTheme.CAPS_MUTED)
	cap.custom_minimum_size.x = 48
	row.add_child(cap)
	var chips: Array[PanelContainer] = []
	for option in names:
		var chip := HudTheme.panel(HudTheme.CHIP)
		chip.add_child(HudTheme.label(option, HudTheme.NUM, HudTheme.FS_SMALL))
		row.add_child(chip)
		chips.append(chip)
	row.add_child(HudTheme.spacer())
	for key in keys:
		row.add_child(KeyCap.new(key))
	_rows.append(chips)

func apply_state(state: HudState) -> void:
	var indices := [state.shape_index, state.type_index, state.spin_index]
	var context := [state.hole_index, state.strokes, state.putting]
	if not _last.is_empty() and context == _context and indices != _last and not state.putting and not state.in_motion and not state.hole_complete:
		_remaining = SHOW_SECONDS
		visible = true
		set_process(true)
	_last = indices
	_context = context
	if state.putting or state.in_motion or state.hole_complete:
		_hide_picker()
	if visible:
		for row in range(_rows.size()):
			for option in range(_rows[row].size()):
				_style(_rows[row][option], option == indices[row])

func _style(chip: PanelContainer, on: bool) -> void:
	var variation: StringName = HudTheme.CHIP_ON if on else HudTheme.CHIP
	if chip.theme_type_variation != variation:
		chip.theme_type_variation = variation
		var label := chip.get_child(0) as Label
		if on:
			HudTheme.tint(label, HudPalette.INK)
			label.add_theme_font_override("font", HudFonts.condensed(700))
		else:
			HudTheme.untint(label)
			label.remove_theme_font_override("font")

func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_hide_picker()

func _hide_picker() -> void:
	visible = false
	set_process(false)
