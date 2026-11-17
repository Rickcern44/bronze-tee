class_name HoleDefinition
extends Resource
## Supported shapes: curved rounded fairway, elliptical green/tee/water and sinusoidal path.
## Coordinates are meters: X right and Z forward (negative from the tee).

@export_group("Scorecard")
@export var number: int = 1
@export var display_name: String = "Hole 1"
@export var par: int = 4
@export var yards: float = 353.0
@export_group("Positions")
@export var tee_position: Vector2 = Vector2.ZERO
@export var cup_position: Vector2 = Vector2(0.0, -322.7832)
@export var tee_ellipse: Vector4 = Vector4(0.0, -2.0, 7.0, 6.0)
## Offsets from the white tee. Yardage 0 disables extra tees on older holes.
@export var blue_tee_offset: Vector2 = Vector2.ZERO
@export var black_tee_offset: Vector2 = Vector2.ZERO
@export var blue_tee_yards: float = 0.0
@export var black_tee_yards: float = 0.0
@export var green_radii: Vector2 = Vector2(15.5, 14.5)
@export var collar_ratio: float = 1.15
@export_group("Fairway")
@export var fairway_sway: float = 0.8
@export var fairway_sway_frequency: float = 0.012
## Optional ordered centerline points (X, Z) for mapped doglegs; maximum four.
@export var fairway_centerline: Array[Vector2] = []
## Smooth lateral shift in meters; negative bends left. Start/end are distances down-hole.
@export var dogleg_offset: float = 0.0
@export var dogleg_start: float = 210.0
@export var dogleg_end: float = 370.0
@export var fairway_base_width: float = 15.5
@export var fairway_bulge: float = 2.0
@export var fairway_tee_end_z: float = -22.0
@export var fairway_green_end_offset: float = 4.0
@export var first_cut_width: float = 3.0
@export var second_cut_width: float = 6.0
@export var mow_band_length: float = 24.0
@export_group("Elevation")
## Optional little-endian float32 grid, row-major from top-left, relative meters.
@export_file("*.f32") var elevation_file: String = ""
@export var elevation_origin: Vector2 = Vector2.ZERO
@export var elevation_spacing: float = 2.0
@export var elevation_dimensions: Vector2i = Vector2i.ZERO
@export var fairway_height: float = 0.75
@export var fairway_frequency: float = 0.023
@export var cross_height: float = 0.32
@export var cross_x_frequency: float = 0.055
@export var cross_z_frequency: float = 0.017
## Hills: center Z, width and height (meters). Multiple hills can overlap.
@export var hills: Array[Vector3] = []
## Set end greater than start to fade elevation in away from the tee; equal values disable it.
@export var elevation_fade_start: float = 0.0
@export var elevation_fade_end: float = 0.0
@export var green_base_follows_fairway: bool = true
@export var green_base_height: float = 0.0
@export var green_slope: Vector2 = Vector2(0.006, 0.003)
@export var green_wave_height: float = 0.0
@export var green_wave_frequency: Vector2 = Vector2(0.18, 0.13)
@export var green_blend_end: float = 1.6
@export_group("Water")
## Ellipses: center X, center Z, radius X, radius Z. Maximum four.
@export var water_ellipses: Array[Vector4] = []
@export_group("Cart path")
@export var path_center_x: float = 27.0
@export var path_sway: float = 2.0
@export var path_sway_frequency: float = 0.012
@export var path_half_width: float = 1.8
@export var path_start_z: float = 4.0
@export var path_past_cup: float = 15.0
@export_group("Trees")
@export var tree_count: int = 17
@export var tree_spacing: float = 21.0
@export var tree_start_z: float = 3.0
@export var tree_right_x: float = 33.0
@export var tree_left_x: float = -36.0
@export var trees_on_left: bool = true
## Guard trees: X offset from cup, Z offset from cup, scale.
@export var green_guard_trees: Array[Vector3] = []
