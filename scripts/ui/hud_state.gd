class_name HudState
extends RefCounted
## Plain game values pushed to the HUD. Components do all display formatting.
## Distances are in meters unless the name says otherwise.

enum PreviewKind { NONE, LANDING, PUTT }
enum ToastKind { NEUTRAL, ALERT }

# Hole and scorecard
var course_name := "Royal Crest"
var hole_index := 0
var hole_pars := PackedInt32Array()
var hole_yards := 0.0
var tee_name := "WHITE"
var hole_scores := PackedInt32Array()  # completed scores; -1 denotes a hole skipped in debug practice
var strokes := 0
var hole_complete := false
var has_next_hole := false

# Ball and shot
var putting := false
var on_green := false
var in_motion := false
var airborne := false
var has_landed := false
var lie := "Tee"
var shot_lie := "Tee"           # lie the current shot was struck from
var lie_factor := 1.0
var distance_to_pin_m := 0.0
var shot_distance_m := 0.0
var aim_degrees := 0.0
var carry_m := 0.0
var roll_m := 0.0
var backspin_rpm := 0.0
var sidespin_rpm := 0.0

# Wind (relative to the aim line; positive = toward the target / toward the right)
var wind_mph := 0.0
var wind_toward_target_mph := 0.0
var wind_toward_right_mph := 0.0

# Club
var club_name := "Driver"
var club_index := 0
var recommended_club_index := -1
var recommended_yards := 0.0
var recommended_name := ""
var shape_index := 2
var type_index := 0
var spin_index := 0
var swing_speed_mph := 105.0

# Green
var stimp_options := PackedFloat32Array([8.0, 10.0, 12.0])
var stimp_index := 1
var slope_forward_percent := 0.0  # positive = rises toward the target
var slope_right_percent := 0.0    # positive = rises toward the right (ball breaks left)
var putt_aim_degrees := 0.0
var putt_aim_offset_inches := 0.0
var putt_previous_valid := false
var putt_start_distance_m := 0.0

# Swing
var swing_active := false
var backswing_valid := false
var power_locked := false
var backswing_power := 0.0
var last_power := 0.0
var swipe_degrees := 0.0
var last_swipe_degrees := 0.0
var swipe_sensitivity := 1.0
var swipe_deadzone_degrees := 2.0
var swipe_max_degrees := 12.0
var suggested_power := -1.0     # negative when there is no suggestion

# Preview (landing view / putt preview)
var preview_kind := PreviewKind.NONE
var preview_distance_m := 0.0
var preview_surface := ""
var preview_tree_hit := false
var preview_holed := false
var preview_power := 1.0
var preview_roll_m := 0.0
var preview_past_cup_m := 0.0   # positive = ends past the cup, negative = short
var preview_lateral_cup_m := 0.0 # positive = right of the direct line to the cup

# Toast (a new serial shows it again)
var toast_serial := 0
var toast_kind := ToastKind.NEUTRAL
var toast_title := ""
var toast_detail := ""
