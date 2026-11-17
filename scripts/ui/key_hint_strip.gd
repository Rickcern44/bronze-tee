class_name KeyHintStrip
extends PanelContainer
## A row of "[key][key] action" hints. Items look like {"keys": ["A", "D"], "text": "Aim"}.

var _row: HBoxContainer
var _items: Array = []

func _init() -> void:
	theme_type_variation = HudTheme.STRIP
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HudTheme.hbox(6)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)

func set_hints(items: Array) -> void:
	if items == _items:
		return
	_items = items.duplicate(true)
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for i in range(items.size()):
		var item: Dictionary = items[i]
		for key in item.keys:
			_row.add_child(KeyCap.new(key))
		var text := HudTheme.label(item.text, HudTheme.BODY)
		if i < items.size() - 1:
			text.add_theme_constant_override("outline_size", 0)
			var holder := MarginContainer.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_theme_constant_override("margin_right", 8)
			holder.add_child(text)
			_row.add_child(holder)
		else:
			_row.add_child(text)
