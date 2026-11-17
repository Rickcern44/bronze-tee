class_name PreviewPanel
extends PanelContainer
## Text card for the landing view and the putt preview.

const YARDS_PER_METER := 1.0936133
const FEET_PER_METER := 3.28084

var _title: Label
var _key_hint: Label
var _headline: Label
var _helper: Label

func _init() -> void:
	theme_type_variation = HudTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var column := HudTheme.vbox(6)
	add_child(column)
	var header := HudTheme.hbox(6)
	column.add_child(header)
	_title = HudTheme.label("", HudTheme.CAPS)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(KeyCap.new("V"))
	_key_hint = HudTheme.label("", HudTheme.HELPER)
	header.add_child(_key_hint)
	_headline = HudTheme.label("", HudTheme.NUM, HudTheme.FS_TITLE)
	column.add_child(_headline)
	_helper = HudTheme.label("", HudTheme.HELPER)
	_helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_helper.custom_minimum_size.x = 100
	column.add_child(_helper)

func apply_state(state: HudState) -> void:
	visible = state.preview_kind != HudState.PreviewKind.NONE
	if not visible:
		return
	var percent := roundi(state.preview_power * 100.0)
	if state.preview_kind == HudState.PreviewKind.PUTT:
		_title.text = "PUTT PREVIEW"
		_key_hint.text = "to hide"
		var along := 0.0 if state.preview_holed else state.preview_past_cup_m * FEET_PER_METER
		var lateral := 0.0 if state.preview_holed else state.preview_lateral_cup_m * FEET_PER_METER
		_headline.text = "%.1f FT ROLL" % (state.preview_roll_m * FEET_PER_METER)
		_helper.text = "At %d%%: %.1f ft %s · %.1f ft %s. Estimate updates with your swing." % [percent, absf(along), "PAST" if along >= 0.0 else "SHORT", absf(lateral), "RIGHT" if lateral >= 0.0 else "LEFT"]
	else:
		_title.text = "LANDING VIEW"
		_key_hint.text = "to return"
		var yards := roundi(state.preview_distance_m * YARDS_PER_METER)
		var surface := "FIRST CUT" if state.preview_surface == "FirstCut" else state.preview_surface.to_upper()
		if state.preview_tree_hit:
			_headline.text = "TREE · %d YD" % yards
		elif surface == "WATER":
			_headline.text = "WATER · +1 STROKE"
		else:
			_headline.text = "%d YD CARRY · %s" % [yards, surface]
		_helper.text = "At %d%% power. Updates with your backswing." % percent
