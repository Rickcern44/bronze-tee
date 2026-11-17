class_name SwingMeter
extends PanelContainer
## Swing state label, power percentage, power bar and the swipe-direction gauge.

enum Phase { READY, TOO_SHORT, BACKSWING, SWIPE_TO_PUTT, LOCKED, LAST }

var phase := Phase.READY
var power_percent := 0
var _title: Label
var _percent: Label
var _percent_sign: Label
var _bar: PowerBar
var _hint: Label
var _degrees: Label
var _sensitivity: Label
var _gauge: SwipeGauge

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 440
	var column := HudTheme.vbox(8)
	add_child(column)
	var top := HudTheme.hbox(0)
	column.add_child(top)
	_title = HudTheme.label("", HudTheme.CAPS, 15)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(_title)
	_percent = HudTheme.label("0", HudTheme.NUM_BOLD, HudTheme.FS_BIG)
	top.add_child(_percent)
	_percent_sign = HudTheme.label("%", HudTheme.NUM_MUTED, HudTheme.FS_VALUE)
	_percent_sign.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(_percent_sign)
	_bar = PowerBar.new()
	column.add_child(_bar)
	var swipe := HudTheme.hbox(10)
	column.add_child(swipe)
	swipe.add_child(HudTheme.label("SWIPE", HudTheme.CAPS_MUTED))
	_gauge = SwipeGauge.new()
	swipe.add_child(_gauge)
	_degrees = HudTheme.label("", HudTheme.NUM, HudTheme.FS_VALUE)
	_degrees.custom_minimum_size.x = 44
	_degrees.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	swipe.add_child(_degrees)
	swipe.add_child(KeyCap.new(","))
	swipe.add_child(KeyCap.new("."))
	_sensitivity = HudTheme.label("", HudTheme.NUM_MUTED, HudTheme.FS_SMALL)
	swipe.add_child(_sensitivity)
	_hint = HudTheme.label("Hold mouse · pull back · swipe up", HudTheme.HELPER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)

func apply_state(state: HudState) -> void:
	phase = _phase_for(state)
	var fraction := state.backswing_power if state.swing_active and state.backswing_valid else 0.0
	var style := PowerBar.Style.EMPTY
	var title := "Swing · ready"
	match phase:
		Phase.TOO_SHORT:
			title = "Pull down to set power"
			style = PowerBar.Style.TOO_SHORT
		Phase.BACKSWING:
			title = "Backswing · swipe up"
			style = PowerBar.Style.BACKSWING
		Phase.SWIPE_TO_PUTT:
			title = "Swipe up to putt"
			style = PowerBar.Style.BACKSWING
		Phase.LOCKED:
			title = "Release to hit"
			style = PowerBar.Style.LOCKED
		Phase.LAST:
			title = "Last swing"
			style = PowerBar.Style.LAST
			fraction = state.last_power
	power_percent = int(fraction * 100.0)
	_title.text = title.to_upper()
	if phase == Phase.LOCKED:
		HudTheme.tint(_title, HudPalette.LIVE)
	elif phase == Phase.TOO_SHORT:
		HudTheme.tint(_title, HudPalette.CHALK)
	else:
		HudTheme.untint(_title)
	theme_type_variation = HudTheme.PANEL_LIVE if phase == Phase.LOCKED else HudTheme.PANEL
	var too_short := phase == Phase.TOO_SHORT
	_percent.text = "–" if too_short else str(power_percent)
	_percent_sign.visible = not too_short
	if too_short:
		HudTheme.tint(_percent, HudPalette.MUTED)
	else:
		HudTheme.untint(_percent)
	var suggestion := state.suggested_power if state.putting and not state.in_motion else -1.0
	_bar.set_bar(fraction, style, suggestion, state.putting)
	_hint.visible = phase == Phase.READY
	var degrees := state.swipe_degrees if state.swing_active else state.last_swipe_degrees
	_gauge.set_gauge(degrees, state.swipe_max_degrees, state.swipe_deadzone_degrees, state.swing_active)
	_degrees.text = HudFormat.signed(degrees, 1, "°")
	_sensitivity.text = "%.2f×" % state.swipe_sensitivity

func _phase_for(state: HudState) -> Phase:
	if state.swing_active:
		if not state.backswing_valid:
			return Phase.TOO_SHORT
		if state.power_locked:
			return Phase.LOCKED
		return Phase.SWIPE_TO_PUTT if state.putting else Phase.BACKSWING
	if state.has_landed or state.in_motion:
		return Phase.LAST
	return Phase.READY
