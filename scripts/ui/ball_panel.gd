class_name BallPanel
extends PanelContainer
## Lie icon, ball state chip, carry/roll/shot tiles and (while moving) spin tiles.

const YARDS_PER_METER := 1.0936133

var _icon: LieIcon
var _title: Label
var _chip: StateChip
var _distance_grid: GridContainer
var _spin_grid: GridContainer
var _carry: StatTile
var _roll: StatTile
var _shot: StatTile
var _backspin: StatTile
var _sidespin: StatTile

func _init() -> void:
	theme_type_variation = HudTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := HudTheme.vbox(10)
	add_child(column)
	column.add_child(HudTheme.label("BALL & LIE", HudTheme.CAPS))
	var row := HudTheme.hbox(12)
	column.add_child(row)
	_icon = LieIcon.new()
	row.add_child(_icon)
	var texts := HudTheme.vbox(6)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)
	_title = HudTheme.label("", HudTheme.NUM_BOLD, HudTheme.FS_STAT)
	texts.add_child(_title)
	_chip = StateChip.new()
	texts.add_child(_chip)
	_distance_grid = _grid(column, 3)
	_carry = _tile(_distance_grid, "CARRY", "YD")
	_roll = _tile(_distance_grid, "ROLL", "YD")
	_shot = _tile(_distance_grid, "SHOT", "YD")
	_spin_grid = _grid(column, 2)
	_backspin = _tile(_spin_grid, "BACKSPIN", "RPM")
	_sidespin = _tile(_spin_grid, "SIDESPIN", "RPM")

func _grid(parent: Control, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	return grid

func _tile(grid: GridContainer, caption: String, unit: String) -> StatTile:
	var tile := StatTile.new(caption, unit)
	grid.add_child(tile)
	return tile

func chip_state() -> StateChip.State:
	return _chip.state

func apply_state(state: HudState) -> void:
	var leaving := state.in_motion and state.airborne and not state.has_landed
	var shown_lie := state.shot_lie if leaving else state.lie
	_icon.set_lie(shown_lie)
	var lie_label := "FIRST CUT" if shown_lie == "FirstCut" else shown_lie.to_upper()
	var title := ("FROM " + lie_label) if leaving else ("%s · %d%%" % [lie_label, roundi(state.lie_factor * 100.0)])
	if _title.text != title:
		_title.text = title
	var chip := StateChip.State.AT_REST
	if state.hole_complete:
		chip = StateChip.State.HOLED
	elif state.in_motion:
		chip = StateChip.State.BOUNCING if (state.airborne and state.has_landed) else (StateChip.State.IN_FLIGHT if state.airborne else StateChip.State.ROLLING)
	_chip.set_state(chip)
	theme_type_variation = HudTheme.PANEL_LIVE if state.in_motion else HudTheme.PANEL
	_distance_grid.visible = state.in_motion or not state.putting
	_spin_grid.visible = state.in_motion
	if _distance_grid.visible:
		_carry.set_value(str(roundi(state.carry_m * YARDS_PER_METER)))
		_roll.set_value("%.1f" % (state.roll_m * YARDS_PER_METER))
		_shot.set_value(str(roundi(state.shot_distance_m * YARDS_PER_METER)))
	if _spin_grid.visible:
		_backspin.set_value(HudFormat.thousands(roundi(state.backspin_rpm)))
		_sidespin.set_value(HudFormat.signed(state.sidespin_rpm, 0))
