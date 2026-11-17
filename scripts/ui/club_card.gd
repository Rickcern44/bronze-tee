class_name ClubCard
extends PanelContainer
## Club name, recommendation chip, and pip rows for shape, type, spin and swing speed.

const SHAPES := ["HOOK", "DRAW", "STRAIGHT", "FADE", "SLICE"]
const TYPES := ["NORMAL", "FLOP", "PUNCH", "STINGER"]
const SPINS := ["NORMAL", "BACKSPIN", "TOPSPIN"]

var _keys_row: HBoxContainer
var _name: Label
var _chip: PanelContainer
var _chip_label: Label
var _summary: Label
var _setup: VBoxContainer
var _divider: Control
var _shape_pips: PipRow
var _type_pips: PipRow
var _spin_pips: PipRow
var _shape_value: Label
var _type_value: Label
var _spin_value: Label
var _speed_value: Label

func _init() -> void:
	theme_type_variation = HudTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := HudTheme.vbox(9)
	add_child(column)
	var header := HudTheme.hbox(4)
	column.add_child(header)
	header.add_child(HudTheme.label("CLUB", HudTheme.CAPS))
	header.add_child(HudTheme.spacer())
	_keys_row = HudTheme.hbox(4)
	_keys_row.add_child(KeyCap.new("Q"))
	_keys_row.add_child(KeyCap.new("E"))
	header.add_child(_keys_row)
	var name_row := HudTheme.hbox(6)
	column.add_child(name_row)
	_name = HudTheme.label("", HudTheme.NUM_BOLD, HudTheme.FS_NAME)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	name_row.add_child(_name)
	_chip = HudTheme.panel(HudTheme.CHIP_BRONZE)
	_chip_label = HudTheme.label("", HudTheme.NUM_BOLD, HudTheme.FS_SMALL, HudPalette.INK)
	_chip.add_child(_chip_label)
	name_row.add_child(_chip)
	_summary = HudTheme.label("", HudTheme.NUM_MUTED, 15)
	column.add_child(_summary)
	_setup = HudTheme.vbox(9)
	column.add_child(_setup)
	_setup.add_child(HudTheme.divider())
	_shape_pips = PipRow.new(SHAPES.size(), 9)
	_type_pips = PipRow.new(TYPES.size(), 12)
	_spin_pips = PipRow.new(SPINS.size(), 17)
	_shape_value = _setup_row("SHAPE", _shape_pips, ["U", "I"])
	_type_value = _setup_row("TYPE", _type_pips, ["J", "K"])
	_spin_value = _setup_row("SPIN", _spin_pips, ["B"])
	_speed_value = _setup_row("SPEED", null, ["[", "]"])

func _setup_row(caption: String, pips: PipRow, keys: Array) -> Label:
	var row := HudTheme.hbox(8)
	_setup.add_child(row)
	var cap := HudTheme.label(caption, HudTheme.CAPS_MUTED)
	cap.custom_minimum_size.x = 42
	row.add_child(cap)
	if pips != null:
		row.add_child(pips)
	var value := HudTheme.label("", HudTheme.NUM)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.clip_text = true
	row.add_child(value)
	for key in keys:
		row.add_child(KeyCap.new(key))
	return value

func recommendation_text() -> String:
	return _chip_label.text if _chip.visible else ""

func apply_state(state: HudState) -> void:
	var title := state.club_name.to_upper()
	_assign(_name, title)
	_name.add_theme_font_size_override("font_size", HudTheme.FS_NAME if title.length() <= 8 else (30 if title.length() <= 10 else 24))
	var detail_hidden := state.in_motion or state.putting
	_setup.visible = not detail_hidden
	_keys_row.visible = not state.in_motion
	_summary.visible = detail_hidden
	if state.putting:
		_assign(_summary, "PUTT · ROLLS STRAIGHT OFF THE FACE")
	elif state.in_motion:
		_assign(_summary, "%s · %s · %s SPIN" % [SHAPES[state.shape_index], TYPES[state.type_index], SPINS[state.spin_index]])
	var recommended := state.recommended_club_index >= 0 and not state.in_motion and not state.hole_complete
	_chip.visible = recommended
	if recommended:
		var match_now := state.recommended_club_index == state.club_index
		_chip.theme_type_variation = HudTheme.CHIP_BRONZE if match_now else HudTheme.CHIP_OUTLINE
		HudTheme.tint(_chip_label, HudPalette.INK if match_now else HudPalette.MUTED)
		if match_now:
			_assign(_chip_label, "REC" if state.putting else "REC · %d YD" % roundi(state.recommended_yards))
		else:
			_assign(_chip_label, "REC · %s" % state.recommended_name.to_upper())
	if _setup.visible:
		_shape_pips.set_active(state.shape_index)
		_type_pips.set_active(state.type_index)
		_spin_pips.set_active(state.spin_index)
		_assign(_shape_value, SHAPES[state.shape_index])
		_assign(_type_value, TYPES[state.type_index])
		_assign(_spin_value, SPINS[state.spin_index])
		_assign(_speed_value, "%d MPH DRIVER REF" % roundi(state.swing_speed_mph))

static func _assign(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
