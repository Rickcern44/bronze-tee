class_name KeyCap
extends PanelContainer
## A small keyboard key cap such as Q, E or ESC.

var _label: Label

func _init(key_text: String = "") -> void:
	theme_type_variation = HudTheme.KEY
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(20, 20)
	_label = HudTheme.label(key_text, HudTheme.NUM, HudTheme.FS_CAPTION)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

func set_key(key_text: String) -> void:
	_label.text = key_text
