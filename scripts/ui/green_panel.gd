class_name GreenPanel
extends PanelContainer
## Stimp selector plus uphill/downhill and break tiles, shown while the putter is selected.

const FLAT_PERCENT := 0.05

var _stimp: SegmentedControl
var _slope_caption: Label
var _slope_value: Label
var _slope_arrow: ArrowIcon
var _break_caption: Label
var _break_value: Label
var _break_arrow: ArrowIcon
var _aim_readout: Label
var _previous_readout: Label

func _init() -> void:
	theme_type_variation = HudTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := HudTheme.vbox(10)
	add_child(column)
	var header := HudTheme.hbox(6)
	column.add_child(header)
	header.add_child(HudTheme.label("GREEN", HudTheme.CAPS))
	header.add_child(HudTheme.spacer())
	header.add_child(HudTheme.label("speed", HudTheme.HELPER, HudTheme.FS_CAPTION))
	header.add_child(KeyCap.new("G"))
	var stimp_row := HudTheme.hbox(10)
	column.add_child(stimp_row)
	stimp_row.add_child(HudTheme.label("STIMP", HudTheme.CAPS_MUTED))
	_stimp = SegmentedControl.new()
	stimp_row.add_child(_stimp)
	var tiles := GridContainer.new()
	tiles.columns = 2
	tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tiles.add_theme_constant_override("h_separation", 6)
	column.add_child(tiles)
	var slope_parts := _tile(tiles)
	_slope_caption = slope_parts[0]
	_slope_arrow = slope_parts[1]
	_slope_value = slope_parts[2]
	var break_parts := _tile(tiles)
	_break_caption = break_parts[0]
	_break_arrow = break_parts[1]
	_break_value = break_parts[2]
	_aim_readout = HudTheme.label("", HudTheme.NUM, 18)
	column.add_child(_aim_readout)
	_previous_readout = HudTheme.label("", HudTheme.HELPER, HudTheme.FS_CAPTION)
	column.add_child(_previous_readout)
	var note := HudTheme.label("Arrows point downhill. H toggles the read; V shows putt numbers. Scroll or +/− to zoom; Shift + A/D makes fine aim changes.", HudTheme.HELPER, HudTheme.FS_CAPTION)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 100
	column.add_child(note)

func _tile(grid: GridContainer) -> Array:
	var tile := HudTheme.panel(HudTheme.WELL)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(tile)
	var column := HudTheme.vbox(4)
	tile.add_child(column)
	var caption := HudTheme.label("", HudTheme.CAPS_MUTED, HudTheme.FS_MICRO)
	column.add_child(caption)
	var row := HudTheme.hbox(6)
	column.add_child(row)
	var arrow := ArrowIcon.new()
	row.add_child(arrow)
	var value := HudTheme.label("", HudTheme.NUM_BOLD, HudTheme.FS_TITLE)
	row.add_child(value)
	return [caption, arrow, value]

func apply_state(state: HudState) -> void:
	var options := PackedStringArray()
	for option in state.stimp_options:
		options.append(str(roundi(option)))
	_stimp.set_options(options, state.stimp_index)
	var forward := state.slope_forward_percent
	var flat := absf(forward) < FLAT_PERCENT
	_slope_caption.text = "LEVEL" if flat else ("UPHILL" if forward > 0.0 else "DOWNHILL")
	_slope_arrow.visible = not flat
	_slope_arrow.set_direction(ArrowIcon.Direction.UP if forward > 0.0 else ArrowIcon.Direction.DOWN)
	_slope_value.text = "%.1f%%" % absf(forward)
	var side := state.slope_right_percent
	var straight := absf(side) < FLAT_PERCENT
	# Ground rising to the right pushes the ball left.
	_break_caption.text = "STRAIGHT" if straight else ("BREAKS LEFT" if side > 0.0 else "BREAKS RIGHT")
	_break_arrow.visible = not straight
	_break_arrow.set_direction(ArrowIcon.Direction.LEFT if side > 0.0 else ArrowIcon.Direction.RIGHT)
	_break_value.text = "%.1f%%" % absf(side)
	if not is_finite(state.putt_aim_offset_inches):
		_aim_readout.text = "AIM %.2f° FROM CUP" % state.putt_aim_degrees
	elif absf(state.putt_aim_offset_inches) < 0.05:
		_aim_readout.text = "AIM AT CUP · 0.0 IN"
	else:
		_aim_readout.text = "AIM %.1f IN %s" % [absf(state.putt_aim_offset_inches), "RIGHT" if state.putt_aim_offset_inches > 0 else "LEFT"]
	_previous_readout.visible = state.putt_previous_valid
	_previous_readout.text = "LAST PUTT: %.1f FT FROM CUP · %.1f FT ROLLED" % [state.putt_start_distance_m * 3.28084, state.roll_m * 3.28084]
