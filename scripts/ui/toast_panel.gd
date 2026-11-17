class_name ToastPanel
extends PanelContainer
## A short message that appears when the toast serial changes and fades after a few seconds.

const SHOW_SECONDS := 4.0
const FADE_SECONDS := 0.4

var _serial := 0
var _remaining := 0.0
var _title: Label
var _detail: Label
var _icon: Control

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	var row := HudTheme.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	_icon = ToastIcon.new()
	row.add_child(_icon)
	var column := HudTheme.vbox(4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	_title = HudTheme.label("", HudTheme.NUM_BOLD, HudTheme.FS_TITLE)
	column.add_child(_title)
	_detail = HudTheme.label("", HudTheme.HELPER)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = 100
	column.add_child(_detail)

func apply_state(state: HudState) -> void:
	if state.hole_complete:
		_dismiss()
		return
	if state.toast_serial == _serial:
		return
	_serial = state.toast_serial
	if state.toast_title.is_empty():
		_dismiss()
		return
	var alert := state.toast_kind == HudState.ToastKind.ALERT
	theme_type_variation = HudTheme.PANEL_ALERT if alert else HudTheme.PANEL
	_icon.visible = alert
	_title.text = state.toast_title.to_upper()
	_detail.text = state.toast_detail
	_detail.visible = not state.toast_detail.is_empty()
	modulate.a = 1.0
	visible = true
	_remaining = SHOW_SECONDS
	set_process(true)

func _process(delta: float) -> void:
	_remaining -= delta
	modulate.a = clampf(_remaining / FADE_SECONDS, 0.0, 1.0)
	if _remaining <= 0.0:
		_dismiss()

func _dismiss() -> void:
	visible = false
	set_process(false)
