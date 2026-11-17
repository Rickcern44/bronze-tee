class_name DebugMenu
extends Control
## Full-screen input shield with a dynamically generated hole picker.

signal hole_selected(index: int)
var buttons: Array[Button] = []

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.015, .68)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = HudTheme.PANEL
	panel.custom_minimum_size = Vector2(350, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var column := HudTheme.vbox(10)
	panel.add_child(column)
	column.add_child(HudTheme.label("DEBUG  /  HOLE SELECT", HudTheme.CAPS, 18))
	column.add_child(HudTheme.label("Choose a hole to start a practice round.", HudTheme.BODY))
	column.add_child(HudTheme.label("Jumping clears the current round scores.", HudTheme.HELPER))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 180
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "HoleList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	column.add_child(HudTheme.label("F3 / ESC  CLOSE   •   1–9  SELECT", HudTheme.CAPS_MUTED))

func setup(holes: Array) -> void:
	var list: VBoxContainer = find_child("HoleList", true, false)
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	buttons.clear()
	for i in range(holes.size()):
		var hole = holes[i]
		var button := Button.new()
		button.text = "%d   HOLE %d     PAR %d  •  %d YD" % [i + 1, i + 1, int(hole.par), roundi(hole.yards)]
		button.custom_minimum_size = Vector2(0, 38)
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_override("font", HudFonts.condensed(600))
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", HudPalette.CHALK)
		button.add_theme_color_override("font_hover_color", HudPalette.CHALK)
		button.add_theme_stylebox_override("normal", HudDraw.box(HudPalette.WELL, 5))
		button.add_theme_stylebox_override("hover", HudDraw.box(HudPalette.PANEL, 5, HudPalette.BRONZE, 1))
		button.add_theme_stylebox_override("focus", HudDraw.box(Color.TRANSPARENT, 5, HudPalette.LIVE, 1))
		button.pressed.connect(hole_selected.emit.bind(i))
		list.add_child(button)
		buttons.append(button)
