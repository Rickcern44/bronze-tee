class_name StatTile
extends PanelContainer
## A small well with a caption and a value plus unit, e.g. CARRY 142 YD.

var _caption: Label
var _value: Label
var _unit: Label

func _init(caption: String = "", unit: String = "") -> void:
	theme_type_variation = HudTheme.WELL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := HudTheme.vbox(3)
	add_child(column)
	_caption = HudTheme.label(caption, HudTheme.CAPS_MUTED, HudTheme.FS_MICRO)
	column.add_child(_caption)
	var row := HudTheme.hbox(4)
	column.add_child(row)
	_value = HudTheme.label("0", HudTheme.NUM_BOLD, HudTheme.FS_TILE)
	row.add_child(_value)
	_unit = HudTheme.label(unit, HudTheme.NUM_MUTED, HudTheme.FS_CAPTION)
	_unit.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_unit)

func set_value(text: String) -> void:
	if _value.text != text:
		_value.text = text
