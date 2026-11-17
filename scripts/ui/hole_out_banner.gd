class_name HoleOutBanner
extends PanelContainer
## Shown when the ball drops: the hole result, strokes, round score and the next-step keys.

var _heading: Label
var _result: Label
var _summary: Label
var _next_keys: HBoxContainer
var _replay_text: Label

func _init() -> void:
	theme_type_variation = HudTheme.PANEL_BANNER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 520
	visible = false
	var row := HudTheme.hbox(16)
	add_child(row)
	var left := HudTheme.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	_heading = HudTheme.label("", HudTheme.CAPS, 0, HudPalette.LIVE)
	left.add_child(_heading)
	_result = HudTheme.label("", HudTheme.NUM_BOLD, 56)
	left.add_child(_result)
	var right := HudTheme.vbox(8)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	_summary = HudTheme.label("", HudTheme.NUM, HudTheme.FS_TITLE)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_summary)
	var keys := HudTheme.hbox(6)
	keys.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(keys)
	_next_keys = HudTheme.hbox(6)
	_next_keys.add_child(KeyCap.new("N"))
	_next_keys.add_child(HudTheme.label("Next hole", HudTheme.BODY, HudTheme.FS_SMALL))
	keys.add_child(_next_keys)
	keys.add_child(KeyCap.new("R"))
	_replay_text = HudTheme.label("Replay", HudTheme.BODY, HudTheme.FS_SMALL)
	keys.add_child(_replay_text)

static func result_name(strokes: int, par: int) -> String:
	var relative := strokes - par
	if strokes == 1:
		return "HOLE IN ONE"
	match relative:
		-3: return "ALBATROSS"
		-2: return "EAGLE"
		-1: return "BIRDIE"
		0: return "PAR"
		1: return "BOGEY"
		2: return "DOUBLE BOGEY"
		3: return "TRIPLE BOGEY"
	return HudFormat.relative_to_par(relative) if relative > 0 else "ALBATROSS"

func apply_state(state: HudState) -> void:
	visible = state.hole_complete
	if not visible:
		return
	var par := state.hole_pars[state.hole_index] if state.hole_pars.size() > state.hole_index else 4
	var total := 0
	var par_total := 0
	for i in range(state.hole_scores.size()):
		if state.hole_scores[i] >= 0:
			total += state.hole_scores[i]
			par_total += state.hole_pars[i]
	_heading.text = ("HOLE %d COMPLETE" % (state.hole_index + 1)) if state.has_next_hole else "ROUND COMPLETE"
	_result.text = result_name(state.strokes, par)
	_summary.text = "%d %s · ROUND %s" % [state.strokes, "STROKE" if state.strokes == 1 else "STROKES", HudFormat.relative_to_par(total - par_total)]
	_next_keys.visible = state.has_next_hole
	_replay_text.text = "Replay" if state.has_next_hole else "New round"
