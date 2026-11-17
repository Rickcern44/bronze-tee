class_name Hud
extends Control
## HUD root. main.gd fills a HudState and calls apply_state(); every component formats its own text.

var state: HudState

var hole_card: HoleCard
var preview_panel: PreviewPanel
var toast_panel: ToastPanel
var distance_readout: DistanceReadout
var hole_out_banner: HoleOutBanner
var shot_setup_picker: ShotSetupPicker
var wind_panel: WindPanel
var club_card: ClubCard
var green_panel: GreenPanel
var ball_panel: BallPanel
var swing_meter: SwingMeter
var aim_hints: KeyHintStrip
var system_hints: KeyHintStrip

func _init() -> void:
	theme = HudTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	state = HudState.new()
	_build_left_column()
	_build_center()
	_build_right_column()
	_build_bottom()

func _build_left_column() -> void:
	var column := HudTheme.vbox(12)
	column.position = Vector2(20, 20)
	column.custom_minimum_size.x = 340
	add_child(column)
	hole_card = HoleCard.new()
	column.add_child(hole_card)
	preview_panel = PreviewPanel.new()
	column.add_child(preview_panel)
	toast_panel = ToastPanel.new()
	column.add_child(toast_panel)

func _build_center() -> void:
	var column := HudTheme.vbox(12)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.set_anchors_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = 20
	add_child(column)
	distance_readout = DistanceReadout.new()
	distance_readout.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(distance_readout)
	hole_out_banner = HoleOutBanner.new()
	hole_out_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(hole_out_banner)
	shot_setup_picker = ShotSetupPicker.new()
	shot_setup_picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(shot_setup_picker)

func _build_right_column() -> void:
	var column := HudTheme.vbox(12)
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.offset_left = -296
	column.offset_right = -20
	column.offset_top = 20
	add_child(column)
	wind_panel = WindPanel.new()
	column.add_child(wind_panel)
	club_card = ClubCard.new()
	column.add_child(club_card)
	green_panel = GreenPanel.new()
	column.add_child(green_panel)
	ball_panel = BallPanel.new()
	column.add_child(ball_panel)

func _build_bottom() -> void:
	swing_meter = SwingMeter.new()
	swing_meter.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	swing_meter.grow_horizontal = Control.GROW_DIRECTION_BOTH
	swing_meter.grow_vertical = Control.GROW_DIRECTION_BEGIN
	swing_meter.offset_bottom = -20
	add_child(swing_meter)
	aim_hints = KeyHintStrip.new()
	aim_hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	aim_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	aim_hints.offset_left = 20
	aim_hints.offset_bottom = -20
	add_child(aim_hints)
	system_hints = KeyHintStrip.new()
	system_hints.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	system_hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	system_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	system_hints.offset_right = -20
	system_hints.offset_bottom = -20
	add_child(system_hints)
	system_hints.set_hints([{"keys": ["F3"], "text": "Holes"}, {"keys": ["T"], "text": "Tees"}, {"keys": ["R"], "text": "Restart"}, {"keys": ["ESC"], "text": "Quit"}])

## Push a full snapshot of game state to every component.
func apply_state(new_state: HudState) -> void:
	state = new_state
	hole_card.apply_state(state)
	preview_panel.apply_state(state)
	toast_panel.apply_state(state)
	distance_readout.apply_state(state)
	hole_out_banner.apply_state(state)
	shot_setup_picker.apply_state(state)
	wind_panel.apply_state(state)
	wind_panel.visible = not state.putting
	club_card.apply_state(state)
	green_panel.visible = state.putting and not state.in_motion
	if green_panel.visible:
		green_panel.apply_state(state)
	ball_panel.apply_state(state)
	swing_meter.apply_state(state)
	var preview_label := "Putt numbers" if state.putting else "Landing view"
	aim_hints.visible = not state.in_motion
	var hints := [
		{"keys": ["A", "D"], "text": "Aim 0.25°" if state.on_green else "Aim"},
		{"keys": ["V"], "text": preview_label},
	]
	if state.putting:
		hints.append({"keys": ["H"], "text": "Green read"})
		hints.append({"keys": ["SHIFT"], "text": "Fine aim"})
	aim_hints.set_hints(hints)
