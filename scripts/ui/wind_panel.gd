class_name WindPanel
extends PanelContainer
## Wind dial, speed, and helping/hurting and crosswind chips.

const STRONG_MPH := 15.0

var _dial: WindDial
var _speed: Label
var _unit: Label
var _chips: HBoxContainer
var _along: Label
var _across: Label

func _init() -> void:
	theme_type_variation = HudTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := HudTheme.vbox(10)
	add_child(column)
	var header := HudTheme.hbox(4)
	column.add_child(header)
	header.add_child(HudTheme.label("WIND", HudTheme.CAPS))
	header.add_child(HudTheme.spacer())
	for item in [["W", "speed"], ["X", "dir"]]:
		header.add_child(KeyCap.new(item[0]))
		var caption := HudTheme.label(item[1], HudTheme.HELPER, HudTheme.FS_CAPTION)
		header.add_child(caption)
	var row := HudTheme.hbox(14)
	column.add_child(row)
	_dial = WindDial.new()
	row.add_child(_dial)
	var speed_row := HudTheme.hbox(6)
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(speed_row)
	_speed = HudTheme.label("", HudTheme.NUM_BOLD, 48)
	speed_row.add_child(_speed)
	_unit = HudTheme.label("MPH", HudTheme.NUM_MUTED, HudTheme.FS_VALUE)
	speed_row.add_child(_unit)
	_chips = HudTheme.hbox(6)
	column.add_child(_chips)
	_along = _chip()
	_across = _chip()

func _chip() -> Label:
	var holder := HudTheme.panel(HudTheme.CHIP)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := HudTheme.label("", HudTheme.NUM, HudTheme.FS_SMALL)
	holder.add_child(label)
	_chips.add_child(holder)
	return label

func apply_state(state: HudState) -> void:
	var calm := state.wind_mph < 0.5
	var along := state.wind_toward_target_mph
	var across := state.wind_toward_right_mph
	_dial.set_wind(along, across, calm, along < 0.0 and state.wind_mph >= STRONG_MPH)
	_speed.text = "CALM" if calm else str(roundi(state.wind_mph))
	_speed.add_theme_font_size_override("font_size", 40 if calm else 48)
	_unit.visible = not calm
	_chips.visible = not calm
	if calm:
		return
	_along.text = ("%d HELPING" % roundi(along)) if along >= 0.0 else ("%d HURTING" % roundi(-along))
	_across.text = ("%d LEFT TO RIGHT" % roundi(across)) if across >= 0.0 else ("%d RIGHT TO LEFT" % roundi(-across))
