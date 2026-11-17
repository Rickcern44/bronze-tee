class_name StateChip
extends PanelContainer
## Ball state chip: at rest, in flight, bouncing, rolling or holed.

enum State { AT_REST, IN_FLIGHT, BOUNCING, ROLLING, HOLED }

const NAMES := ["AT REST", "IN FLIGHT", "BOUNCING", "ROLLING", "HOLED"]

var state := State.AT_REST
var _label: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_label = HudTheme.label("", HudTheme.NUM_BOLD, 13)
	add_child(_label)
	set_state(State.AT_REST, true)

func set_state(new_state: State, force: bool = false) -> void:
	if new_state == state and not force:
		return
	state = new_state
	_label.text = NAMES[state]
	var text_color := HudPalette.INK
	match state:
		State.AT_REST:
			theme_type_variation = HudTheme.CHIP_OUTLINE
			text_color = HudPalette.MUTED
		State.IN_FLIGHT, State.BOUNCING: theme_type_variation = HudTheme.CHIP_LIVE
		State.ROLLING: theme_type_variation = HudTheme.CHIP_BRONZE
		State.HOLED: theme_type_variation = HudTheme.CHIP_CHALK
	HudTheme.tint(_label, text_color)
