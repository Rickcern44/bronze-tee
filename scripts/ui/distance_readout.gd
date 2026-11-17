class_name DistanceReadout
extends PanelContainer
## Centred distance readout: yards to the pin, the live shot distance, or feet to the cup.

enum Mode { TO_PIN, SHOT, TO_CUP_FEET, SHOT_FEET }

const YARDS_PER_METER := 1.0936133
const FEET_PER_METER := 3.28084

var mode := Mode.TO_PIN
var _value: Label
var _unit: Label
var _sub: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HudTheme.hbox(14)
	add_child(row)
	_value = HudTheme.label("0", HudTheme.NUM_BOLD, HudTheme.FS_HERO)
	_value.custom_minimum_size.x = 108
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_value)
	var column := HudTheme.vbox(6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)
	_unit = HudTheme.label("", HudTheme.CAPS, 15)
	column.add_child(_unit)
	_sub = HudTheme.label("", HudTheme.NUM_MUTED, 15)
	column.add_child(_sub)
	_apply_mode(Mode.TO_PIN, true)

func apply_state(state: HudState) -> void:
	var new_mode := Mode.TO_PIN
	if state.in_motion:
		new_mode = Mode.SHOT_FEET if state.putting else Mode.SHOT
	elif state.putting:
		new_mode = Mode.TO_CUP_FEET
	_apply_mode(new_mode, false)
	var to_pin_yards := state.distance_to_pin_m * YARDS_PER_METER
	var to_pin_feet := state.distance_to_pin_m * FEET_PER_METER
	match mode:
		Mode.TO_PIN:
			_assign(_value, str(roundi(to_pin_yards)))
			_assign(_sub, "AIM " + HudFormat.signed(state.aim_degrees, 2, "°"))
		Mode.SHOT:
			_assign(_value, "%.1f" % (state.shot_distance_m * YARDS_PER_METER))
			_assign(_sub, "%d TO PIN" % roundi(to_pin_yards))
		Mode.TO_CUP_FEET:
			_assign(_value, "%.1f" % to_pin_feet)
			_assign(_sub, "HOLED" if state.hole_complete else _stroke_goal(state))
		Mode.SHOT_FEET:
			_assign(_value, "%.1f" % (state.shot_distance_m * FEET_PER_METER))
			_assign(_sub, "%.1f TO CUP" % to_pin_feet)

func _apply_mode(new_mode: Mode, force: bool) -> void:
	if new_mode == mode and not force:
		return
	mode = new_mode
	var moving := mode == Mode.SHOT or mode == Mode.SHOT_FEET
	theme_type_variation = HudTheme.PANEL_COMPACT_LIVE if moving else HudTheme.PANEL_COMPACT
	if moving:
		HudTheme.tint(_value, HudPalette.LIVE)
		HudTheme.tint(_unit, HudPalette.LIVE)
	else:
		HudTheme.untint(_value)
		HudTheme.untint(_unit)
	_unit.text = ["YD TO PIN", "YD SHOT", "FT TO CUP", "FT SHOT"][mode]

## "FOR BIRDIE" etc: what holing this putt scores.
func _stroke_goal(state: HudState) -> String:
	var par := state.hole_pars[state.hole_index] if state.hole_pars.size() > state.hole_index else 4
	var relative := state.strokes + 1 - par
	if state.strokes + 1 == 1:
		return "FOR ACE"
	match relative:
		-3: return "FOR ALBATROSS"
		-2: return "FOR EAGLE"
		-1: return "FOR BIRDIE"
		0: return "FOR PAR"
		1: return "FOR BOGEY"
	return "FOR %s" % HudFormat.relative_to_par(relative)

static func _assign(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
