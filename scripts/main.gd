extends Node3D

var elevation_samples := PackedFloat32Array()
var _elevation_grid_cache: Dictionary = {}
const TEE_NAMES = ["WHITE", "BLUE", "BLACK"]
var tee_index := 0
var imported_green_height := 0.0
var imported_green_slope := Vector2.ZERO

# Simulation uses meters; distances shown to players are in yards.
const TREE_MODELS = [
	preload("res://assets/forest/Flat_Tree_Oak_large_green.glb"),
	preload("res://assets/forest/Flat_Tree_Pine_large.glb"),
	preload("res://assets/forest/Flat_Tree_Park_large_green.glb"),
]
const CLUBS = [
	{"name": "Driver", "speed": 69.60, "loft": 22.0},
	{"name": "3 Wood", "speed": 67.64, "loft": 21.0},
	{"name": "5 Wood", "speed": 62.52, "loft": 23.0},
	{"name": "7 Wood", "speed": 58.13, "loft": 25.0},
	{"name": "4 Hybrid", "speed": 56.38, "loft": 26.0},
	{"name": "5 Iron", "speed": 53.04, "loft": 27.0},
	{"name": "6 Iron", "speed": 49.80, "loft": 29.0},
	{"name": "7 Iron", "speed": 46.81, "loft": 31.0},
	{"name": "8 Iron", "speed": 43.60, "loft": 34.0},
	{"name": "9 Iron", "speed": 40.67, "loft": 37.0},
	{"name": "Pitching Wedge", "speed": 37.82, "loft": 40.0},
	{"name": "Sand Wedge", "speed": 31.69, "loft": 46.0},
	{"name": "Lob Wedge", "speed": 29.45, "loft": 52.0},
	{"name": "Putter", "speed": 8.00, "loft": 0.0},
]
# Positive curve bends to the right of the aim line (right-handed convention).
const SHAPES = [
	{"name": "Hook", "curve": -0.0008},
	{"name": "Draw", "curve": -0.00035},
	{"name": "Straight", "curve": 0.0},
	{"name": "Fade", "curve": 0.00035},
	{"name": "Slice", "curve": 0.0008},
]
const SHOT_TYPES = ["Normal", "Flop", "Punch", "Stinger"]
const SPIN_MODES = ["Normal", "Backspin", "Topspin"]
const GRAVITY = 9.81
const AIR_DRAG = 0.0022
const WIND_SPEEDS_MPH = [0, 5, 10, 15, 20]
const MPH_TO_MPS = 0.44704
const REFERENCE_SWING_MPH = 105.0
const ROLL_DECEL = 7.5
# Keep putting feedback in step with the C# simulation.
const STIMP_LAUNCH_SPEED = 1.83
const GREEN_SLOPE_FACTOR = 5.0 / 7.0
const PUTTER_ROLL_SPEED_FACTOR = 1.0 - (1.0 - 0.35) * 2.0 / 7.0
const GREEN_SPEEDS = [8.0, 10.0, 12.0]
const PUTTER_POWER_EXPONENT = 1.5
const YARDS_PER_METER = 1.0936133
const BACKSWING_FOR_FULL_POWER = 180.0
const MIN_BACKSWING = 20.0
const FORWARD_TO_HIT = 25.0
const SWIPE_DEADZONE_DEGREES = 2.0
const MAX_SWIPE_DEGREES = 12.0
const COURSE = preload("res://resources/courses/royal_crest.tres")
# The course resource controls the round order.
var HOLES: Array = []
var active_hole: Resource
var hole_index := 0
var hole_scores: Array[int] = []
# Terrain surfaces, shared by _surface_at and the terrain shader.
enum Surface { GREEN, COLLAR, FAIRWAY, FIRST_CUT, SECOND_CUT, DEEP_ROUGH, WATER, PATH, TEE }
var FIRST_CUT_WIDTH := 3.0
var SECOND_CUT_WIDTH := 6.0 # Visual only: second cut and deep rough are both "Rough".
var GREEN_RADII := Vector2(15.5, 14.5)
var COLLAR_RATIO := 1.15
var TEE_BOX := Vector4(0.0, -2.0, 7.0, 6.0) # x, z centre and x, z radii
var FAIRWAY_SWAY := 0.8
var FAIRWAY_SWAY_FREQUENCY := 0.012
var FAIRWAY_BASE_WIDTH := 15.5
var FAIRWAY_BULGE := 2.0
var FAIRWAY_TEE_END_Z := -22.0
var FAIRWAY_GREEN_END_OFFSET := 4.0
var MOW_BAND_LENGTH := 24.0
var PATH_CENTER_X := 27.0
var PATH_SWAY := 2.0
var PATH_SWAY_FREQUENCY := 0.012
var PATH_HALF_WIDTH := 1.8
var PATH_START_Z := 4.0
var PATH_PAST_CUP := 15.0
const FLAG_COLOR := Color(0.08, 0.30, 0.92) # course flag cloth, blue
const MAX_WATER_FEATURES := 4
const TERRAIN_ALBEDO_GAIN := 0.75 # keeps the bright scene lighting from clipping the textures
const TERRAIN_TEXTURES := {
	"green_texture": "res://assets/textures/library/turf/green.png",
	"collar_texture": "res://assets/textures/library/turf/collar.png",
	"fairway_light_texture": "res://assets/textures/library/turf/fairway_light.png",
	"fairway_dark_texture": "res://assets/textures/library/turf/fairway_dark.png",
	"first_cut_texture": "res://assets/textures/library/turf/first_cut.png",
	"second_cut_texture": "res://assets/textures/library/turf/second_cut.png",
	"deep_rough_texture": "res://assets/textures/library/turf/deep_rough.png",
	"water_texture": "res://assets/textures/terrain/water.png",
	"path_texture": "res://assets/textures/library/ground/cart_path.png",
}
var CUP := Vector3(0, 0, -322.7832) # Repositioned to each hole's white-tee distance.
const CUP_RADIUS = 0.10795 / 2.0
const CUP_DEPTH = 0.1016
const BALL_RADIUS = 0.02135
var TEE: Vector3 = Vector3(0, BALL_RADIUS, 0)

var physics_bridge: Node
var wind_index := 0
# Direction is where the wind blows, in degrees around the hole.
var wind_direction := 0.0
var wind_rng := RandomNumberGenerator.new()
var tree_obstacles: Array[Dictionary] = []
var trail: BallTrail
var trail_points: Array[Vector3]:
	get: return trail.points
var tree_hit_cooldown := 0.0
var strokes := 0
var hole_complete := false
var shot_start := TEE
var shot_lie := "Tee"
var club_index := 0
var swing_speed_mph := 105.0
var green_speed_index := 1
var shape_index := 2
var shot_type_index := 0
var spin_index := 0
var backspin_rpm := 0.0
var sidespin_rpm := 0.0
var aim := 0.0
var ball_position := TEE
var velocity := Vector3.ZERO
var in_motion := false
var airborne := false
var peak_height := 0.0
var carry := 0.0
var roll_distance := 0.0
var has_landed := false
var swing_active := false
var forward_distance := 0.0
var forward_lateral := 0.0
var swipe_sensitivity := 1.0
var backswing := 0.0
var last_power := 0.0
var last_direction := 0.0
var message := "Drag down, then swipe up to swing"
var ball: MeshInstance3D
var camera: Camera3D
var aim_line: MeshInstance3D
var hud: Hud
var debug_menu: DebugMenu
var hud_state := HudState.new()
var recommendation_key: Array = []
var recommended_club := -1
var recommended_yards := 0.0
var ball_shadow: MeshInstance3D
var landing_view := false
var landing_marker: LandingMarker
var putt_preview: PuttPreview
var green_read: GreenRead
var green_read_enabled := true
var putt_zoom_fov := 42.0
var landing_prediction: Dictionary = {}
var prediction_key: Array = []
var terrain_material: ShaderMaterial

func _ready() -> void:
	assert(not COURSE.holes.is_empty(), "A course must contain at least one hole")
	HOLES = COURSE.holes.duplicate()
	_configure_hole(0)
	wind_rng.randomize()
	_randomize_wind()
	physics_bridge = load("res://scripts/PhysicsBridge.cs").new()
	physics_bridge.name = "PhysicsBridge"
	add_child(physics_bridge)
	_build_world()
	_build_ui()
	_reset_ball()
	_update_hud()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func _box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.material_override = _material(color)
	item.position = pos
	add_child(item)
	return item

# One configuration feeds terrain, shader uniforms, ball queries and the HUD.
func _configure_hole(index: int) -> void:
	hole_index = index
	active_hole = HOLES[index]
	# Replace the active array; clearing it would also empty its cached value.
	elevation_samples = PackedFloat32Array()
	if not active_hole.elevation_file.is_empty():
		var count: int = active_hole.elevation_dimensions.x * active_hole.elevation_dimensions.y
		if _elevation_grid_cache.has(active_hole.elevation_file):
			elevation_samples = _elevation_grid_cache[active_hole.elevation_file]
		else:
			var data := FileAccess.get_file_as_bytes(active_hole.elevation_file)
			assert(active_hole.elevation_spacing > 0.0 and active_hole.elevation_dimensions.x >= 2 and active_hole.elevation_dimensions.y >= 2 and data.size() == count * 4, "Invalid elevation grid")
			elevation_samples.resize(count)
			for i in range(count):
				elevation_samples[i] = data.decode_float(i * 4)
			_elevation_grid_cache[active_hole.elevation_file] = elevation_samples
	FIRST_CUT_WIDTH = active_hole.first_cut_width
	SECOND_CUT_WIDTH = active_hole.second_cut_width
	GREEN_RADII = active_hole.green_radii
	COLLAR_RATIO = active_hole.collar_ratio
	TEE_BOX = active_hole.tee_ellipse
	FAIRWAY_SWAY = active_hole.fairway_sway
	FAIRWAY_SWAY_FREQUENCY = active_hole.fairway_sway_frequency
	FAIRWAY_BASE_WIDTH = active_hole.fairway_base_width
	FAIRWAY_BULGE = active_hole.fairway_bulge
	FAIRWAY_TEE_END_Z = active_hole.fairway_tee_end_z
	FAIRWAY_GREEN_END_OFFSET = active_hole.fairway_green_end_offset
	MOW_BAND_LENGTH = active_hole.mow_band_length
	PATH_CENTER_X = active_hole.path_center_x
	PATH_SWAY = active_hole.path_sway
	PATH_SWAY_FREQUENCY = active_hole.path_sway_frequency
	PATH_HALF_WIDTH = active_hole.path_half_width
	PATH_START_Z = active_hole.path_start_z
	PATH_PAST_CUP = active_hole.path_past_cup
	assert(active_hole.dogleg_end > active_hole.dogleg_start, "Dogleg end must be after its start")
	assert(active_hole.fairway_centerline.is_empty() or active_hole.fairway_centerline.size() >= 2, "A mapped fairway needs at least two points")
	for i in range(active_hole.fairway_centerline.size() - 1):
		assert(active_hole.fairway_centerline[i].y > active_hole.fairway_centerline[i + 1].y, "Mapped fairway points must progress down the hole")
	assert(active_hole.water_ellipses.size() <= MAX_WATER_FEATURES, "A hole supports at most four water ellipses")
	for hill in active_hole.hills:
		assert(hill.y > 0.0, "Hill width must be positive")
	assert(active_hole.green_radii.x > 0 and active_hole.green_radii.y > 0 and active_hole.cup_position.y < 0, "Green radii must be positive and cup Z must be negative")
	CUP = Vector3(active_hole.cup_position.x, 0.0, active_hole.cup_position.y)
	if not elevation_samples.is_empty():
		_fit_imported_green()
	var tee: Vector2 = active_hole.tee_position + _selected_tee_offset()
	TEE = Vector3(tee.x, _ground_height(tee.x, tee.y) + BALL_RADIUS, tee.y)

func _selected_tee_offset() -> Vector2:
	if tee_index == 1 and active_hole.blue_tee_yards > 0.0: return active_hole.blue_tee_offset
	if tee_index == 2 and active_hole.black_tee_yards > 0.0: return active_hole.black_tee_offset
	return Vector2.ZERO

func _selected_tee_name() -> String:
	if active_hole.blue_tee_yards <= 0.0 or active_hole.black_tee_yards <= 0.0: return "WHITE"
	return TEE_NAMES[tee_index]

func _selected_tee_yards() -> float:
	if tee_index == 1 and active_hole.blue_tee_yards > 0.0: return active_hole.blue_tee_yards
	if tee_index == 2 and active_hole.black_tee_yards > 0.0: return active_hole.black_tee_yards
	return active_hole.yards

func _tee_ellipses() -> Array[Vector4]:
	var boxes: Array[Vector4] = [TEE_BOX]
	if active_hole.blue_tee_yards > 0.0:
		boxes.append(TEE_BOX + Vector4(active_hole.blue_tee_offset.x, active_hole.blue_tee_offset.y, 0, 0))
	if active_hole.black_tee_yards > 0.0:
		boxes.append(TEE_BOX + Vector4(active_hole.black_tee_offset.x, active_hole.black_tee_offset.y, 0, 0))
	return boxes

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.48, 0.7, 0.86)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.85, 0.92, 1.0)
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	# The same height function drives both this mesh and the ball simulation.
	_box(Vector3(0, -30.0 if not elevation_samples.is_empty() else -2.0, -150), Vector3(800, 0.2, 900), Color("2B6424")) # deep rough colour beyond the terrain mesh
	_build_terrain()
	_build_tee_box()
	# The second hole has a lake on the left and more open space around its tee.
	var tree_count: int = active_hole.tree_count
	for i in range(tree_count):
		var z := -float(i) * float(active_hole.tree_spacing) + float(active_hole.tree_start_z)
		var right_x := float(active_hole.tree_right_x) + float((i * 7) % 9) + _fairway_dogleg_shift(z)
		_add_tree(Vector3(right_x, _ground_height(right_x, z), z), 0.85 + float((i + 2) % 4) * 0.12)
		if active_hole.trees_on_left and i % 3 != 1:
			var left_x := float(active_hole.tree_left_x) - float((i * 5) % 15) + _fairway_dogleg_shift(z - 4.0)
			_add_tree(Vector3(left_x, _ground_height(left_x, z - 4.0), z - 4.0), 0.85 + float(i % 4) * 0.12)
	for guard in active_hole.green_guard_trees:
		var x: float = CUP.x + guard.x
		var z: float = CUP.z + guard.y
		_add_tree(Vector3(x, _ground_height(x, z), z), guard.z)
	for yards in range(50, int(active_hole.yards), 50):
		var distance: float = yards / YARDS_PER_METER
		if distance > -CUP.z: continue
		_add_marker(yards, distance)
	_build_cup()
	var pole := _box(Vector3(CUP.x, _ground_height(CUP.x, CUP.z) + 2.0, CUP.z), Vector3(0.012, 4.0, 0.012), Color(0.95, 0.94, 0.82))
	pole.name = "CupPole"
	var flag := _box(Vector3(CUP.x + 0.9, _ground_height(CUP.x, CUP.z) + 3.6, CUP.z), Vector3(1.8, 0.8, 0.08), FLAG_COLOR)
	flag.name = "CupFlag"
	ball_shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.045
	shadow_mesh.bottom_radius = 0.045
	shadow_mesh.height = 0.02
	ball_shadow.mesh = shadow_mesh
	ball_shadow.material_override = _material(Color(0.16, 0.30, 0.12))
	add_child(ball_shadow)
	trail = BallTrail.new()
	trail.ground_height = Callable(self, "_ground_height")
	add_child(trail)
	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	ball.mesh = sphere
	ball.material_override = _material(Color.WHITE)
	# Enlarge only the display mesh away from the green so long shots remain visible.
	# The green view keeps the ball and cup at their true relative sizes.
	var on_putting_surface := club_index == CLUBS.size() - 1 or (has_landed and _on_green(ball_position))
	var display_scale := 1.0 if on_putting_surface else 3.0
	ball.scale = Vector3.ONE * display_scale
	ball.position = ball_position + Vector3.UP * (BALL_RADIUS * (display_scale - 1.0) if not airborne else 0.0)
	add_child(ball)
	_build_landing_marker()
	aim_line = _box(Vector3(0, 0.09, -8), Vector3(0.05, 0.02, 16), HudPalette.BRONZE_LABEL)
	var aim_material := FxMeshBuilder.make_material()
	aim_material.vertex_color_use_as_albedo = false
	aim_material.albedo_color = Color(HudPalette.BRONZE_LABEL, 0.75)
	aim_line.material_override = aim_material
	camera = Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.position = TEE + Vector3(0, 7, 12)
	camera.look_at(TEE + Vector3(0, 1, -25))

func _build_landing_marker() -> void:
	landing_marker = LandingMarker.new()
	landing_marker.ground_height = Callable(self, "_ground_height")
	add_child(landing_marker)
	putt_preview = PuttPreview.new()
	putt_preview.ground_height = Callable(self, "_ground_height")
	add_child(putt_preview)
	green_read = GreenRead.new()
	green_read.ground_height = Callable(self, "_ground_height")
	green_read.ground_slope = Callable(self, "_ground_slope")
	green_read.cup = CUP
	green_read.radii = GREEN_RADII
	add_child(green_read)

func _build_tee_box() -> void:
	# The terrain shader paints the mown tee surface; only a low edge and the
	# markers are separate meshes. The height function remains the source of ball physics.
	var tee_box := Node3D.new()
	tee_box.name = "TeeBox"
	add_child(tee_box)
	var boxes := _tee_ellipses()
	var colors := [Color(0.96, 0.97, 0.93), Color("3976d5"), Color("171c1d")]
	for box_index in range(boxes.size()):
		_build_tee_pad(tee_box, boxes[box_index], colors[box_index], TEE_NAMES[box_index])

func _build_tee_pad(parent: Node3D, box: Vector4, color: Color, label: String) -> void:
	var segments := 64
	var edge_surface := SurfaceTool.new()
	edge_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(segments):
		var a := TAU * float(segment) / float(segments)
		var b := TAU * float(segment + 1) / float(segments)
		for item in [[a, 1.0], [a, 1.12], [b, 1.12], [a, 1.0], [b, 1.12], [b, 1.0]]:
			var angle: float = item[0]
			var radius: float = item[1]
			var c := cos(angle)
			var d := sin(angle)
			var x := box.x + c * box.z * radius
			var z := box.y + d * box.w * radius
			var height := 0.04 if radius < 1.01 else 0.005
			edge_surface.add_vertex(Vector3(x, _ground_height(x, z) + height, z))
	edge_surface.generate_normals()
	var edge := MeshInstance3D.new()
	edge.name = label.capitalize() + "TeeEdge"
	edge.mesh = edge_surface.commit()
	var edge_material := _material(Color("4C9734")) # first-cut green from the terrain palette
	edge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge.material_override = edge_material
	parent.add_child(edge)
	# Markers sit just ahead of each tee position, one on each side.
	for side in [-1, 1]:
		var x := box.x + float(side) * 2.4
		var z := box.y - 0.45
		var marker := MeshInstance3D.new()
		marker.name = label.capitalize() + ("MarkerLeft" if side < 0 else "MarkerRight")
		var mesh := SphereMesh.new()
		mesh.radius = 0.28
		mesh.height = 0.56
		marker.mesh = mesh
		var marker_material := _material(color)
		marker_material.roughness = 0.45
		marker.material_override = marker_material
		marker.position = Vector3(x, _ground_height(x, z) + 0.28, z)
		parent.add_child(marker)

func _sample_imported_elevation(x: float, z: float) -> float:
	var size: Vector2i = active_hole.elevation_dimensions
	var gx: float = clampf((x - active_hole.elevation_origin.x) / active_hole.elevation_spacing, 0.0, size.x - 1.0)
	var gz: float = clampf((active_hole.elevation_origin.y - z) / active_hole.elevation_spacing, 0.0, size.y - 1.0)
	var ix := mini(floori(gx), size.x - 2)
	var iz := mini(floori(gz), size.y - 2)
	var a := lerpf(elevation_samples[iz * size.x + ix], elevation_samples[iz * size.x + ix + 1], gx - ix)
	var b := lerpf(elevation_samples[(iz + 1) * size.x + ix], elevation_samples[(iz + 1) * size.x + ix + 1], gx - ix)
	return lerpf(a, b, gz - iz)

# Fit a gentle plane to samples over the green. Lidar captures broad elevation,
# but interpolation and vegetation can give small greens unplayable slopes.
func _fit_imported_green() -> void:
	var sum_h := 0.0
	var sum_xh := 0.0
	var sum_zh := 0.0
	var sum_x2 := 0.0
	var sum_z2 := 0.0
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			var dx: float = ix * GREEN_RADII.x * 0.4
			var dz: float = iz * GREEN_RADII.y * 0.4
			var height := _sample_imported_elevation(CUP.x + dx, CUP.z + dz)
			sum_h += height
			sum_xh += dx * height
			sum_zh += dz * height
			sum_x2 += dx * dx
			sum_z2 += dz * dz
	imported_green_height = sum_h / 25.0
	imported_green_slope = Vector2(sum_xh / sum_x2, sum_zh / sum_z2).limit_length(0.02)

func _ground_height(x: float, z: float) -> float:
	if not elevation_samples.is_empty():
		var terrain := _sample_imported_elevation(x, z)
		var distance := Vector2((x - CUP.x) / GREEN_RADII.x, (z - CUP.z) / GREEN_RADII.y).length()
		var green_weight: float = 1.0 - smoothstep(1.0, active_hole.green_blend_end, distance)
		var green := imported_green_height + (x - CUP.x) * imported_green_slope.x + (z - CUP.z) * imported_green_slope.y
		return lerpf(terrain, green, green_weight)
	# All holes use the same terrain recipe, with features supplied by their resource.
	var fairway: float = active_hole.fairway_height * sin(-z * active_hole.fairway_frequency) + active_hole.cross_height * sin(x * active_hole.cross_x_frequency) * sin(-z * active_hole.cross_z_frequency)
	for hill in active_hole.hills:
		fairway += hill.z * exp(-pow((z - hill.x) / hill.y, 2.0))
	if active_hole.elevation_fade_end > active_hole.elevation_fade_start:
		fairway *= smoothstep(active_hole.elevation_fade_start, active_hole.elevation_fade_end, -z)
	var green_distance := Vector2((x - CUP.x) / GREEN_RADII.x, (z - CUP.z) / GREEN_RADII.y).length()
	var green_weight: float = 1.0 - smoothstep(1.0, active_hole.green_blend_end, green_distance)
	var green_base: float = active_hole.green_base_height
	if active_hole.green_base_follows_fairway:
		green_base += active_hole.fairway_height * sin(-CUP.z * active_hole.fairway_frequency)
	var green: float = green_base + (x - CUP.x) * active_hole.green_slope.x + (z - CUP.z) * active_hole.green_slope.y
	green += active_hole.green_wave_height * sin((x - CUP.x) * active_hole.green_wave_frequency.x) * sin((z - CUP.z) * active_hole.green_wave_frequency.y)
	return lerpf(fairway, green, green_weight)

func _fairway_dogleg_shift(z: float) -> float:
	if active_hole.fairway_centerline.size() >= 2:
		var points: Array[Vector2] = active_hole.fairway_centerline
		for i in range(points.size() - 1):
			if z >= points[i + 1].y:
				var t := clampf((points[i].y - z) / (points[i].y - points[i + 1].y), 0.0, 1.0)
				return lerpf(points[i].x, points[i + 1].x, t)
		return points[-1].x
	return active_hole.dogleg_offset * smoothstep(active_hole.dogleg_start, active_hole.dogleg_end, -z)

func _fairway_center(z: float) -> float:
	return FAIRWAY_SWAY * sin(-z * FAIRWAY_SWAY_FREQUENCY) + _fairway_dogleg_shift(z)

func _in_ellipse(x: float, z: float, cx: float, cz: float, rx: float, rz: float) -> bool:
	return Vector2((x - cx) / rx, (z - cz) / rz).length_squared() < 1.0

# Approximate features visible in the reference map, not survey coordinates.
func _water_features() -> Array:
	return active_hole.water_ellipses

func _in_water(pos: Vector3) -> bool:
	for feature in _water_features():
		if _in_ellipse(pos.x, pos.z, feature[0], feature[1], feature[2], feature[3]): return true
	return false

func _in_bunker(_pos: Vector3) -> bool:
	# No bunker is visible on the supplied first-hole map.
	return false

func _green_distance(x: float, z: float) -> float:
	return Vector2((x - CUP.x) / GREEN_RADII.x, (z - CUP.z) / GREEN_RADII.y).length()

# Single classification of every terrain point. The terrain shader mirrors this
# order (see _update_terrain_uniforms and shaders/terrain.gdshader), and the
# gameplay lie (_lie) is derived from the same helpers. SECOND_CUT vs DEEP_ROUGH
# is visual only: both are "Rough" for gameplay.
func _surface_at(x: float, z: float) -> int:
	if _in_water(Vector3(x, 0.0, z)): return Surface.WATER
	var green_distance := _green_distance(x, z)
	if green_distance < 1.0: return Surface.GREEN
	if green_distance < COLLAR_RATIO: return Surface.COLLAR
	if _on_path(x, z): return Surface.PATH
	for box in _tee_ellipses():
		if _in_ellipse(x, z, box.x, box.y, box.z, box.w): return Surface.TEE
	var edge := _fairway_edge_distance(x, z)
	if edge <= 0.0: return Surface.FAIRWAY
	if edge <= FIRST_CUT_WIDTH: return Surface.FIRST_CUT
	if edge <= FIRST_CUT_WIDTH + SECOND_CUT_WIDTH: return Surface.SECOND_CUT
	return Surface.DEEP_ROUGH

func _terrain_vertex(x: float, z: float) -> Vector3:
	return Vector3(x, _ground_height(x, z), z)

# Cut the terrain mesh around the cup and connect its circular rim to grid-aligned edges.
func _cup_patch_bounds() -> Vector4:
	var left := floorf((CUP.x - CUP_RADIUS + 100.0) / 2.0) * 2.0 - 100.0
	var right := ceilf((CUP.x + CUP_RADIUS + 100.0) / 2.0) * 2.0 - 100.0
	var top := 25.0 - floorf((25.0 - (CUP.z + CUP_RADIUS)) / 2.0) * 2.0
	var bottom := 25.0 - ceilf((25.0 - (CUP.z - CUP_RADIUS)) / 2.0) * 2.0
	return Vector4(left, right, bottom, top)

func _terrain_add_point(surface: SurfaceTool, point: Vector3) -> void:
	surface.add_vertex(point)

func _add_cup_terrain(surface: SurfaceTool, bounds: Vector4) -> void:
	var angles: Array[float] = []
	for i in range(64):
		angles.append(TAU * float(i) / 64.0)
	for corner in [Vector2(bounds.x, bounds.z), Vector2(bounds.x, bounds.w), Vector2(bounds.y, bounds.z), Vector2(bounds.y, bounds.w)]:
		angles.append(fposmod(atan2(corner.y - CUP.z, corner.x - CUP.x), TAU))
	angles.sort()
	for i in range(angles.size()):
		var points: Array[Vector3] = []
		for angle in [angles[i], angles[(i + 1) % angles.size()]]:
			var direction := Vector2(cos(angle), sin(angle))
			var tx := INF if absf(direction.x) < 0.000001 else ((bounds.y if direction.x > 0 else bounds.x) - CUP.x) / direction.x
			var tz := INF if absf(direction.y) < 0.000001 else ((bounds.w if direction.y > 0 else bounds.z) - CUP.z) / direction.y
			var outer := Vector2(CUP.x, CUP.z) + direction * minf(tx, tz)
			var inner := Vector2(CUP.x, CUP.z) + direction * CUP_RADIUS
			points.append(_terrain_vertex(inner.x, inner.y))
			points.append(_terrain_vertex(outer.x, outer.y))
		for index in [0, 1, 2, 1, 3, 2]:
			_terrain_add_point(surface, points[index])

func _build_cup() -> void:
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		var a := TAU * float(i) / 64.0
		var b := TAU * float(i + 1) / 64.0
		var pa := Vector2(CUP.x + cos(a) * CUP_RADIUS, CUP.z + sin(a) * CUP_RADIUS)
		var pb := Vector2(CUP.x + cos(b) * CUP_RADIUS, CUP.z + sin(b) * CUP_RADIUS)
		var top_a := Vector3(pa.x, _ground_height(pa.x, pa.y), pa.y)
		var top_b := Vector3(pb.x, _ground_height(pb.x, pb.y), pb.y)
		var low_a := top_a - Vector3.UP * CUP_DEPTH
		var low_b := top_b - Vector3.UP * CUP_DEPTH
		for point in [top_a, low_a, top_b, low_a, low_b, top_b]:
			walls.add_vertex(point)
	walls.generate_normals()
	var wall_mesh := MeshInstance3D.new()
	wall_mesh.name = "CupWalls"
	wall_mesh.mesh = walls.commit()
	var material := _material(Color(0.22, 0.22, 0.20))
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_mesh.material_override = material
	add_child(wall_mesh)
	var bottom := MeshInstance3D.new()
	bottom.name = "CupBottom"
	var mesh := CylinderMesh.new()
	mesh.top_radius = CUP_RADIUS
	mesh.bottom_radius = CUP_RADIUS
	mesh.height = 0.002
	bottom.mesh = mesh
	bottom.material_override = _material(Color(0.035, 0.04, 0.03))
	bottom.position = Vector3(CUP.x, _ground_height(CUP.x, CUP.z) - CUP_DEPTH, CUP.z)
	add_child(bottom)

func _build_terrain() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var bounds := _cup_patch_bounds()
	# Extend past the green on longer holes; keep the original minimum extent.
	var z_top := 25.0
	for box in _tee_ellipses():
		z_top = maxf(z_top, 25.0 + ceilf((box.y + box.w + 15.0 - 25.0) / step) * step)
	var z_segments := maxi(250, ceili((z_top - (CUP.z - 35.0)) / step))
	var x_start := minf(-100.0, floorf((CUP.x - 60.0) / step) * step)
	var x_end := 100.0
	for point in active_hole.fairway_centerline:
		x_end = maxf(x_end, ceilf((point.x + 60.0) / step) * step)
	var x_segments := ceili((x_end - x_start) / step)
	for ix in range(x_segments):
		for iz in range(z_segments):
			var x := x_start + ix * step
			var z := z_top - iz * step
			if x >= bounds.x and x + step <= bounds.y and z <= bounds.w and z - step >= bounds.z:
				continue
			var points := [_terrain_vertex(x, z), _terrain_vertex(x + step, z), _terrain_vertex(x, z - step), _terrain_vertex(x + step, z - step)]
			for index in [0, 1, 2, 1, 3, 2]:
				var point: Vector3 = points[index]
				surface.add_vertex(point)
	_add_cup_terrain(surface, bounds)
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.name = "CourseTerrain"
	terrain.mesh = surface.commit()
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	for uniform_name in TERRAIN_TEXTURES:
		terrain_material.set_shader_parameter(uniform_name, load(TERRAIN_TEXTURES[uniform_name]))
	_update_terrain_uniforms()
	terrain.material_override = terrain_material
	add_child(terrain)

# Pushes every hole-dependent classification parameter to the terrain shader.
# Called when the terrain is built, which happens on every _load_hole.
func _update_terrain_uniforms() -> void:
	var water := _water_features()
	assert(water.size() <= MAX_WATER_FEATURES, "Raise MAX_WATER_FEATURES and the shader array size")
	var ellipses := PackedVector4Array()
	ellipses.resize(MAX_WATER_FEATURES)
	for i in range(water.size()):
		ellipses[i] = Vector4(water[i][0], water[i][1], water[i][2], water[i][3])
	var m := terrain_material
	m.set_shader_parameter("water_ellipses", ellipses)
	m.set_shader_parameter("water_count", water.size())
	m.set_shader_parameter("cup", Vector2(CUP.x, CUP.z))
	m.set_shader_parameter("green_radii", GREEN_RADII)
	m.set_shader_parameter("collar_ratio", COLLAR_RATIO)
	m.set_shader_parameter("tee_ellipse", TEE_BOX)
	var boxes := _tee_ellipses()
	var extra_tees := PackedVector4Array()
	extra_tees.resize(2)
	for i in range(1, boxes.size()): extra_tees[i - 1] = boxes[i]
	m.set_shader_parameter("extra_tees", extra_tees)
	m.set_shader_parameter("extra_tee_count", boxes.size() - 1)
	m.set_shader_parameter("path_center_x", PATH_CENTER_X)
	m.set_shader_parameter("path_sway", PATH_SWAY)
	m.set_shader_parameter("path_sway_frequency", PATH_SWAY_FREQUENCY)
	m.set_shader_parameter("path_half_width", PATH_HALF_WIDTH)
	m.set_shader_parameter("path_z_range", Vector2(CUP.z - PATH_PAST_CUP, PATH_START_Z))
	m.set_shader_parameter("fairway_sway", FAIRWAY_SWAY)
	m.set_shader_parameter("fairway_sway_frequency", FAIRWAY_SWAY_FREQUENCY)
	m.set_shader_parameter("dogleg_offset", active_hole.dogleg_offset)
	m.set_shader_parameter("dogleg_start", active_hole.dogleg_start)
	m.set_shader_parameter("dogleg_end", active_hole.dogleg_end)
	var centerline := PackedVector2Array()
	centerline.resize(4)
	assert(active_hole.fairway_centerline.size() <= 4, "At most four fairway centerline points")
	for i in range(active_hole.fairway_centerline.size()):
		centerline[i] = active_hole.fairway_centerline[i]
	m.set_shader_parameter("fairway_centerline", centerline)
	m.set_shader_parameter("fairway_centerline_count", active_hole.fairway_centerline.size())
	m.set_shader_parameter("fairway_base_width", FAIRWAY_BASE_WIDTH)
	m.set_shader_parameter("fairway_bulge", FAIRWAY_BULGE)
	m.set_shader_parameter("fairway_tee_end_z", FAIRWAY_TEE_END_Z)
	m.set_shader_parameter("fairway_green_end_offset", FAIRWAY_GREEN_END_OFFSET)
	m.set_shader_parameter("first_cut_width", FIRST_CUT_WIDTH)
	m.set_shader_parameter("second_cut_width", SECOND_CUT_WIDTH)
	m.set_shader_parameter("mow_band_length", MOW_BAND_LENGTH)
	m.set_shader_parameter("albedo_gain", TERRAIN_ALBEDO_GAIN)

func _fairway_width(z: float) -> float:
	return FAIRWAY_BASE_WIDTH + FAIRWAY_BULGE * sin(clampf(-z / -CUP.z, 0.0, 1.0) * PI)

# Signed distance to a rounded fairway, negative inside, in meters.
func _fairway_edge_distance(x: float, z: float) -> float:
	var end_distance := maxf(maxf(z - FAIRWAY_TEE_END_Z, CUP.z - FAIRWAY_GREEN_END_OFFSET - z), 0.0)
	return Vector2(x - _fairway_center(z), end_distance).length() - _fairway_width(z)

func _fairway_contains(x: float, z: float) -> bool:
	return _fairway_edge_distance(x, z) <= 0.0

func _first_cut_contains(x: float, z: float) -> bool:
	var edge := _fairway_edge_distance(x, z)
	return edge > 0.0 and edge <= FIRST_CUT_WIDTH

func _on_path(x: float, z: float) -> bool:
	return absf(x - (PATH_CENTER_X + PATH_SWAY * sin(z * PATH_SWAY_FREQUENCY) + _fairway_dogleg_shift(z))) < PATH_HALF_WIDTH and z < PATH_START_Z and z > CUP.z - PATH_PAST_CUP

func _add_tree(pos: Vector3, scale_factor: float) -> void:
	var variant := posmod(int(absf(pos.z) / 24.0) + (1 if pos.x > 0.0 else 0), TREE_MODELS.size())
	var tree: Node3D = TREE_MODELS[variant].instantiate()
	tree.position = pos
	# Pine models are naturally taller; vary scale modestly across the course.
	var size := scale_factor * (0.65 if variant == 1 else 0.85)
	tree.scale = Vector3.ONE * size
	tree.rotation.y = deg_to_rad(fmod(absf(pos.z * 13.0 + pos.x * 7.0), 360.0))
	add_child(tree)
	# Simple collision volumes match the visible trunks and approximate canopies.
	var trunk_height := (24.0 if variant == 1 else (15.0 if variant == 0 else 16.0)) * size
	tree_obstacles.append({"base": pos, "trunk_radius": 0.55 * size, "height": trunk_height,
		"crown_center": pos + Vector3(0, trunk_height * 0.74, 0), "crown_radius": (4.5 if variant == 1 else 5.5) * size})

func _add_marker(yards: int, distance: float) -> void:
	var label := Label3D.new()
	label.text = str(yards) + " yd"
	label.font_size = 64
	label.pixel_size = 0.02
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var marker_x := -34.0 + _fairway_dogleg_shift(-distance)
	label.position = Vector3(marker_x, _ground_height(marker_x, -distance) + 2, -distance)
	add_child(label)

func _build_ui() -> void:
	hud_state.course_name = COURSE.display_name
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	debug_menu = DebugMenu.new()
	layer.add_child(debug_menu)
	debug_menu.theme = HudTheme.build()
	debug_menu.setup(HOLES)
	debug_menu.hole_selected.connect(_debug_select_hole)
	var pars := PackedInt32Array()
	for hole in HOLES:
		pars.append(int(hole.par))
	hud_state.hole_pars = pars
	hud_state.swipe_deadzone_degrees = SWIPE_DEADZONE_DEGREES
	hud_state.swipe_max_degrees = MAX_SWIPE_DEGREES
	hud_state.stimp_options = PackedFloat32Array(GREEN_SPEEDS)

# Read gameplay input before HUD controls can consume the mouse gesture.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_set_debug_menu_visible(not debug_menu.visible)
			get_viewport().set_input_as_handled()
			return
		if debug_menu.visible:
			if event.keycode == KEY_ESCAPE:
				_set_debug_menu_visible(false)
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_debug_select_hole(int(event.keycode - KEY_1))
			get_viewport().set_input_as_handled()
			return
	if debug_menu.visible:
		return
	if event is InputEventMouseButton and event.pressed and not swing_active and not in_motion and club_index == CLUBS.size() - 1:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			putt_zoom_fov = maxf(20.0, putt_zoom_fov - 5.0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			putt_zoom_fov = minf(70.0, putt_zoom_fov + 5.0)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				if hole_complete and hole_index == HOLES.size() - 1:
					_start_new_round()
				else:
					_reset_ball()
			KEY_T:
				if not in_motion and not swing_active and not hole_complete and strokes == 0 and active_hole.blue_tee_yards > 0.0 and active_hole.black_tee_yards > 0.0:
					var previous_wind_index := wind_index
					var previous_wind_direction := wind_direction
					tee_index = (tee_index + 1) % TEE_NAMES.size()
					_load_hole(hole_index)
					wind_index = previous_wind_index
					wind_direction = previous_wind_direction
					recommendation_key.clear()
					_select_club_for_next_shot()
					_say(_selected_tee_name() + " tees", _selected_tee_name() + " TEES", "T cycles tees before your first shot.")
				elif strokes > 0 and not in_motion:
					_say("Choose tees before your first shot", "TEE SELECTION", "Restart the hole to change tees.")
			KEY_N:
				if hole_complete and hole_index < HOLES.size() - 1:
					_next_hole()
			KEY_V:
				if not in_motion and not hole_complete:
					landing_view = not landing_view
					prediction_key.clear()
			KEY_W:
				if not in_motion: wind_index = (wind_index + 1) % WIND_SPEEDS_MPH.size()
			KEY_X:
				if not in_motion: wind_direction = fmod(wind_direction + 45.0, 360.0)
			KEY_U:
				if not in_motion and not hole_complete and not swing_active and club_index != CLUBS.size() - 1: shape_index = posmod(shape_index - 1, SHAPES.size())
			KEY_I:
				if not in_motion and not hole_complete and not swing_active and club_index != CLUBS.size() - 1: shape_index = posmod(shape_index + 1, SHAPES.size())
			KEY_J:
				if not in_motion and not hole_complete and not swing_active and club_index != CLUBS.size() - 1: shot_type_index = posmod(shot_type_index - 1, SHOT_TYPES.size())
			KEY_K:
				if not in_motion and not hole_complete and not swing_active and club_index != CLUBS.size() - 1: shot_type_index = posmod(shot_type_index + 1, SHOT_TYPES.size())
			KEY_B:
				if not in_motion and not hole_complete and not swing_active and club_index != CLUBS.size() - 1: spin_index = (spin_index + 1) % SPIN_MODES.size()
			KEY_G:
				if not in_motion and not swing_active:
					green_speed_index = (green_speed_index + 1) % GREEN_SPEEDS.size()
					physics_bridge.SetGreenSpeed(GREEN_SPEEDS[green_speed_index])
					prediction_key.clear()
					recommendation_key.clear()
			KEY_H:
				if not in_motion and not swing_active:
					green_read_enabled = not green_read_enabled
			KEY_EQUAL:
				if not in_motion and not swing_active and club_index == CLUBS.size() - 1:
					putt_zoom_fov = maxf(20.0, putt_zoom_fov - 5.0)
			KEY_MINUS:
				if not in_motion and not swing_active and club_index == CLUBS.size() - 1:
					putt_zoom_fov = minf(70.0, putt_zoom_fov + 5.0)
			KEY_COMMA:
				if not in_motion and not swing_active: swipe_sensitivity = maxf(0.5, swipe_sensitivity - 0.25)
			KEY_PERIOD:
				if not in_motion and not swing_active: swipe_sensitivity = minf(2.0, swipe_sensitivity + 0.25)
			KEY_BRACKETLEFT:
				if not in_motion and not swing_active: swing_speed_mph = maxf(70.0, swing_speed_mph - 5.0)
			KEY_BRACKETRIGHT:
				if not in_motion and not swing_active: swing_speed_mph = minf(130.0, swing_speed_mph + 5.0)
			KEY_Q:
				if not in_motion and not hole_complete: club_index = posmod(club_index - 1, CLUBS.size())
			KEY_E:
				if not in_motion and not hole_complete: club_index = posmod(club_index + 1, CLUBS.size())
			KEY_A, KEY_LEFT:
				if not in_motion and not hole_complete: aim -= (0.05 if event.shift_pressed else 0.25) if _on_green(ball_position) else 3.0
			KEY_D, KEY_RIGHT:
				if not in_motion and not hole_complete: aim += (0.05 if event.shift_pressed else 0.25) if _on_green(ball_position) else 3.0
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not in_motion and not hole_complete:
		if event.pressed:
			swing_active = true
			backswing = 0.0
			forward_distance = 0.0
			forward_lateral = 0.0
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			message = "Pull down to set power, then swipe up"
		elif swing_active:
			swing_active = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if backswing >= MIN_BACKSWING and forward_distance >= FORWARD_TO_HIT:
				_hit_ball()
			else:
				_say("Swing cancelled: pull down, then swipe up", "Swing cancelled", "Pull down, then swipe up.")
	if event is InputEventMouseMotion and swing_active:
		# Physical screen pixels are independent of the game's stretch scaling.
		var dy: float = event.screen_relative.y
		if forward_distance == 0.0:
			if dy > 0.0:
				backswing = minf(backswing + dy, BACKSWING_FOR_FULL_POWER)
			elif backswing >= MIN_BACKSWING and dy < 0.0:
				forward_distance = -dy
				forward_lateral += event.screen_relative.x
		elif dy <= 0.0:
			forward_distance += -dy
			forward_lateral += event.screen_relative.x

func _set_debug_menu_visible(show_menu: bool) -> void:
	if show_menu and swing_active:
		swing_active = false
		backswing = 0.0
		forward_distance = 0.0
		forward_lateral = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_say("Swing cancelled", "Swing cancelled", "Choose a hole or close the menu.")
	debug_menu.visible = show_menu

func _debug_select_hole(index: int) -> void:
	if index < 0 or index >= HOLES.size():
		return
	# An unplayed prefix keeps scorecard indices aligned without inventing scores.
	hole_scores.clear()
	for i in range(index):
		hole_scores.append(-1)
	_set_debug_menu_visible(false)
	_load_hole(index)
	_update_hud()

func _swipe_direction() -> float:
	if forward_distance <= 0.0:
		return 0.0
	var angle := rad_to_deg(atan2(forward_lateral, forward_distance))
	var outside_deadzone := maxf(absf(angle) - SWIPE_DEADZONE_DEGREES, 0.0)
	return clampf(signf(angle) * outside_deadzone * 0.65 * swipe_sensitivity, -MAX_SWIPE_DEGREES, MAX_SWIPE_DEGREES)

func _estimated_power() -> float:
	return clampf(backswing / BACKSWING_FOR_FULL_POWER, 0.0, 1.0)

func _lie(pos: Vector3) -> String:
	if pos.distance_to(TEE) < 0.5: return "Tee"
	if _on_green(pos): return "Green"
	if _in_bunker(pos): return "Bunker"
	if _fairway_contains(pos.x, pos.z): return "Fairway"
	if _first_cut_contains(pos.x, pos.z): return "FirstCut"
	return "Rough"

func _lie_factor(pos: Vector3) -> float:
	match _lie(pos):
		"Rough": return 0.82
		"FirstCut": return 0.92
		"Bunker": return 0.62
	return 1.0

func _randomize_wind() -> void:
	wind_index = wind_rng.randi_range(1, WIND_SPEEDS_MPH.size() - 1)
	wind_direction = wind_rng.randf_range(0.0, 360.0)

func _wind_velocity() -> Vector3:
	var angle := deg_to_rad(wind_direction)
	var speed: float = WIND_SPEEDS_MPH[wind_index] * MPH_TO_MPS
	return Vector3(sin(angle), 0.0, -cos(angle)) * speed

func _ground_slope(pos: Vector3) -> Vector2:
	return Vector2(
		(_ground_height(pos.x + 0.2, pos.z) - _ground_height(pos.x - 0.2, pos.z)) / 0.4,
		(_ground_height(pos.x, pos.z + 0.2) - _ground_height(pos.x, pos.z - 0.2)) / 0.4)

func _clear_trail() -> void:
	trail.clear()

func _tree_hit(from: Vector3, to: Vector3) -> bool:
	var segment := to - from
	var length_sq := segment.length_squared()
	for tree in tree_obstacles:
		var base: Vector3 = tree.base
		var center: Vector3 = tree.crown_center
		var t := clampf((center - from).dot(segment) / maxf(length_sq, 0.000001), 0.0, 1.0)
		if from.lerp(to, t).distance_to(center) <= float(tree.crown_radius): return true
		var horizontal_start := Vector2(from.x - base.x, from.z - base.z)
		var horizontal_step := Vector2(segment.x, segment.z)
		var u := clampf(-horizontal_start.dot(horizontal_step) / maxf(horizontal_step.length_squared(), 0.000001), 0.0, 1.0)
		var contact := from.lerp(to, u)
		if Vector2(contact.x - base.x, contact.z - base.z).length() <= float(tree.trunk_radius) + BALL_RADIUS and contact.y >= base.y and contact.y <= base.y + float(tree.height): return true
	return false

func _shot_data(power: float, selected_club: int = -1, selected_aim: float = INF, selected_type: int = -1, swipe_degrees: float = 0.0, selected_shape: int = -1, selected_spin: int = -1) -> Dictionary:
	var lies := {"Tee": 0, "Fairway": 1, "Rough": 2, "Bunker": 3, "Green": 4, "Water": 5, "FirstCut": 6}
	return {
		"start": ball_position, "club": club_index if selected_club < 0 else selected_club,
		"power": power, "aim": aim if is_inf(selected_aim) else selected_aim,
		"shape": shape_index if selected_shape < 0 else selected_shape,
		"type": shot_type_index if selected_type < 0 else selected_type,
		"spin": spin_index if selected_spin < 0 else selected_spin,
		"lie": lies[_lie(ball_position)], "wind": _wind_velocity(),
		"swing_speed": swing_speed_mph, "swipe": swipe_degrees,
	}

func _launch_velocity(power: float, selected_club: int = -1, selected_aim: float = INF, selected_type: int = -1, swipe_degrees: float = 0.0) -> Vector3:
	return physics_bridge.InitialVelocity(_shot_data(power, selected_club, selected_aim, selected_type, swipe_degrees))

func _estimate_full_shot_distance(selected_club: int) -> float:
	# Yardage recommendation: straight normal shot at the cup, ignoring hazards.
	var direction := CUP - ball_position
	var target_aim := rad_to_deg(atan2(direction.x, -direction.z))
	var result: Dictionary = physics_bridge.Forecast(_shot_data(1.0, selected_club, target_aim, 0, 0.0, 2, 0), false, true)
	var pos: Vector3 = result.position
	return Vector2(pos.x - ball_position.x, pos.z - ball_position.z).length()

func _update_recommendation() -> void:
	if in_motion or hole_complete:
		return
	var key := [ball_position, swing_speed_mph, wind_index, wind_direction, green_speed_index, strokes]
	if key == recommendation_key:
		return
	recommendation_key = key
	if _on_green(ball_position):
		recommended_club = CLUBS.size() - 1
		recommended_yards = 0.0
		return
	var target := _distance_to_cup(ball_position)
	var best_error := INF
	for index in range(CLUBS.size() - 1):
		var estimated := _estimate_full_shot_distance(index)
		var error := absf(estimated - target)
		if error < best_error:
			best_error = error
			recommended_club = index
			recommended_yards = estimated * YARDS_PER_METER

func _predict_landing(power: float, swipe_degrees: float = 0.0) -> Dictionary:
	var putting := club_index == CLUBS.size() - 1
	# Path samples are evenly spaced in time: 0.05 s in flight, 0.1 s on the green.
	var result: Dictionary = physics_bridge.ForecastWithPath(_shot_data(power, -1, INF, -1, swipe_degrees), true, false, 6 if putting else 3)
	var surface: String = result.surface
	var tree_hit: bool = result.tree_hit
	if tree_hit and surface != "Tree": surface += " (after tree)"
	return {"position": result.position, "surface": surface, "lie": result.surface, "putt": putting, "tree_hit": tree_hit,
		"holed": result.surface == "Cup", "path": result.path, "path_speed": result.path_speed}

func _hide_previews() -> void:
	landing_marker.hide_marker()
	putt_preview.hide_preview()

func _update_landing_preview() -> void:
	if not landing_view or in_motion or hole_complete:
		_hide_previews()
		return
	var power := _estimated_power() if swing_active and backswing >= MIN_BACKSWING else 1.0
	if not swing_active and club_index == CLUBS.size() - 1 and _on_green(ball_position):
		var heading := deg_to_rad(aim)
		power = _putt_suggested_power(Vector2(sin(heading), -cos(heading)))
	var swipe := _swipe_direction() if swing_active else 0.0
	var key := [ball_position, aim, club_index, shape_index, shot_type_index, spin_index, green_speed_index, swing_speed_mph, wind_index, wind_direction, power, swipe, strokes]
	if key != prediction_key:
		prediction_key = key
		landing_prediction = _predict_landing(power, swipe)
		landing_prediction["power"] = power
		_show_prediction()
	landing_marker.visible = not landing_prediction.putt
	putt_preview.visible = false

# Rebuild the world-space preview; runs only when the prediction key changes.
func _show_prediction() -> void:
	var pos: Vector3 = landing_prediction.position
	var path: PackedVector3Array = landing_prediction.path
	if landing_prediction.putt:
		landing_marker.hide_marker()
		var to_cup := Vector2(CUP.x - ball_position.x, CUP.z - ball_position.z)
		var rolled := Vector2(pos.x - ball_position.x, pos.z - ball_position.z)
		landing_prediction["past_cup"] = rolled.dot(to_cup.normalized()) - to_cup.length()
		var right := Vector2(-to_cup.y, to_cup.x).normalized()
		landing_prediction["lateral_cup"] = (Vector2(pos.x, pos.z) - Vector2(CUP.x, CUP.z)).dot(right)
		putt_preview.hide_preview()
		return
	putt_preview.hide_preview()
	var kind := LandingMarker.Kind.CLEAN
	if landing_prediction.tree_hit:
		kind = LandingMarker.Kind.TREE
	elif landing_prediction.lie == "Water":
		kind = LandingMarker.Kind.WATER
	landing_marker.show_landing(pos, path, kind, Vector2(pos.x - ball_position.x, pos.z - ball_position.z).length())

func _hit_ball() -> void:
	shot_lie = _lie(ball_position)
	last_direction = _swipe_direction()
	physics_bridge.StartShot(_shot_data(_estimated_power(), -1, INF, -1, last_direction))
	var initial: Dictionary = physics_bridge.CurrentShot()
	velocity = initial.velocity
	backspin_rpm = initial.backspin_rpm
	sidespin_rpm = initial.sidespin_rpm
	strokes += 1
	shot_start = ball_position
	_clear_trail()
	tree_hit_cooldown = 0.0
	last_power = _estimated_power()
	landing_view = false
	_hide_previews()
	in_motion = true
	airborne = club_index != CLUBS.size() - 1
	has_landed = not airborne
	peak_height = 0.0
	carry = 0.0
	roll_distance = 0.0
	message = "Putt away!" if not airborne else "Ball in flight"

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and swing_active:
		swing_active = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_say("Swing cancelled — try again", "Swing cancelled", "Try again.")

func _reset_ball() -> void:
	# Restarting a completed hole removes only that hole's recorded score.
	while hole_scores.size() > hole_index:
		hole_scores.pop_back()
	_randomize_wind()
	physics_bridge.CancelShot()
	_clear_trail()
	landing_view = false
	_hide_previews()
	prediction_key.clear()
	recommendation_key.clear()
	ball_position = TEE
	shot_start = TEE
	shot_lie = "Tee"
	strokes = 0
	hole_complete = false
	club_index = 0
	shape_index = 2
	shot_type_index = 0
	spin_index = 0
	backspin_rpm = 0.0
	sidespin_rpm = 0.0
	aim = 0.0
	if active_hole.fairway_centerline.size() >= 2:
		var first_leg: Vector2 = active_hole.fairway_centerline[1] - Vector2(TEE.x, TEE.z)
		aim = rad_to_deg(atan2(first_leg.x, -first_leg.y))
	last_power = 0.0
	last_direction = 0.0
	forward_distance = 0.0
	forward_lateral = 0.0
	velocity = Vector3.ZERO
	in_motion = false
	airborne = false
	swing_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	has_landed = false
	peak_height = 0.0
	carry = 0.0
	roll_distance = 0.0
	_select_club_for_next_shot()
	message = "Drag down, then swipe up to swing"
	# A toast from the previous shot must not carry over to a restarted or new hole.
	_clear_toast()

func _load_hole(index: int) -> void:
	# UI remains; remove all generated 3D nodes and rebuild for this hole.
	for child in get_children():
		if not child is CanvasLayer and child != physics_bridge:
			remove_child(child)
			child.queue_free()
	_configure_hole(index)
	tree_obstacles.clear()
	_build_world()
	_reset_ball()

func _next_hole() -> void:
	if hole_complete and hole_index + 1 < HOLES.size():
		_load_hole(hole_index + 1)

func _start_new_round() -> void:
	hole_scores.clear()
	_load_hole(0)

# Completed holes' strokes minus par.
func _round_relative() -> int:
	var relative := 0
	for i in range(hole_scores.size()):
		if hole_scores[i] >= 0:
			relative += hole_scores[i] - int(HOLES[i].par)
	return relative

func _on_green(pos: Vector3) -> bool:
	return _green_distance(pos.x, pos.z) < 1.0

func _distance_to_cup(pos: Vector3) -> float:
	return Vector2(pos.x - CUP.x, pos.z - CUP.z).length()

func _aim_at_cup() -> void:
	var direction := CUP - ball_position
	aim = rad_to_deg(atan2(direction.x, -direction.z))

func _complete_hole() -> bool:
	if hole_complete:
		return false
	in_motion = false
	hole_complete = true
	if hole_scores.size() == hole_index:
		hole_scores.append(strokes)
	var score := strokes - int(HOLES[hole_index].par)
	var score_text := "PAR" if score == 0 else ("%d UNDER" % -score if score < 0 else "+%d" % score)
	if hole_index + 1 < HOLES.size():
		message = "HOLED IN %d — %s!\nPress N for hole %d" % [strokes, score_text, hole_index + 2]
	else:
		message = "HOLED IN %d — %s!\nROUND COMPLETE  •  R: new round" % [strokes, score_text]
	return true

func _select_club_for_next_shot() -> void:
	# Auto-select only when a new shot begins; players can still change clubs.
	if _on_green(ball_position):
		club_index = CLUBS.size() - 1
	else:
		_update_recommendation()
		if recommended_club >= 0:
			club_index = recommended_club

func _water_penalty() -> void:
	# Simplified stroke-and-distance relief keeps the prototype recoverable.
	strokes += 1
	ball_position = shot_start
	roll_distance = 0.0
	velocity = Vector3.ZERO
	in_motion = false
	airborne = false
	has_landed = false
	_aim_at_cup()
	_select_club_for_next_shot()
	_say("Water: +1 stroke. Replay from previous spot.", "Water \u00b7 +1 stroke", "Replaying from the previous spot.", true)

func _physics_process(delta: float) -> void:
	if debug_menu.visible:
		return
	if in_motion:
		var state: Dictionary = physics_bridge.StepShot(delta)
		backspin_rpm = state.backspin_rpm
		sidespin_rpm = state.sidespin_rpm
		if not state.is_empty():
			ball_position = state.position
			velocity = state.velocity
			carry = state.carry
			roll_distance = state.rollout
			peak_height = state.peak
			has_landed = state.has_landed
			var phase: int = state.phase
			airborne = phase == 0
			trail.track(ball_position, velocity, airborne, has_landed, delta)
			if state.tree_hit:
				trail.mark_tree_hit(ball_position)
				_say("Tree hit!", "Off the tree \u00b7 %d yd" % roundi(Vector2(ball_position.x - shot_start.x, ball_position.z - shot_start.z).length() * YARDS_PER_METER))
			elif state.first_landing:
				var landed_lie := _lie(ball_position).replace("FirstCut", "First Cut")
				_say("Landed on %s" % landed_lie.to_lower(), "Landed \u00b7 %s" % landed_lie, "%d yd carry." % roundi(carry * YARDS_PER_METER))
			if phase == 4:
				trail.mark_water(ball_position)
				trail.set_resting()
				physics_bridge.CancelShot()
				_water_penalty()
			elif phase == 3:
				# Keep scoring and round progression in the Godot game layer.
				trail.set_resting()
				_complete_hole()
				physics_bridge.CancelShot()
			elif phase == 2:
				in_motion = false
				trail.set_resting()
				physics_bridge.CancelShot()
				_aim_at_cup()
				_select_club_for_next_shot()
				if _on_green(ball_position):
					_say("On the green! Putter selected.", "On the green", "Putter selected.")
				else:
					_say("%s selected for next shot" % CLUBS[club_index].name, "%s selected" % CLUBS[club_index].name, "Recommended for the next shot.")

	# Enlarge only the display mesh away from the green so long shots remain visible.
	# The green view keeps the ball and cup at their true relative sizes.
	var on_putting_surface := club_index == CLUBS.size() - 1 or (has_landed and _on_green(ball_position))
	var display_scale := 1.0 if on_putting_surface else 3.0
	ball.scale = Vector3.ONE * display_scale
	ball.position = ball_position + Vector3.UP * (BALL_RADIUS * (display_scale - 1.0) if not airborne else 0.0)
	_update_landing_preview()
	_update_recommendation()
	ball_shadow.position = Vector3(ball_position.x, _ground_height(ball_position.x, ball_position.z) + 0.003, ball_position.z)
	ball_shadow.visible = not _on_green(ball_position)
	var heading := deg_to_rad(aim)
	aim_line.position = ball_position + Vector3(sin(heading) * 8.0, -0.03, -cos(heading) * 8.0)
	aim_line.position.y = _ground_height(aim_line.position.x, aim_line.position.z) + 0.08
	aim_line.rotation.y = -heading
	var view_direction := Vector3(sin(heading), 0, -cos(heading))
	var putting := club_index == CLUBS.size() - 1 and not hole_complete
	if putting and _on_green(ball_position) and not in_motion:
		green_read.show_read(ball_position, shot_start, shot_lie == "Green" and strokes > 0, green_read_enabled)
	else:
		green_read.visible = false
	aim_line.visible = not in_motion and not hole_complete and not putting and not putt_preview.visible
	camera.fov = putt_zoom_fov if putting else 55.0
	if in_motion and not putting and Vector2(velocity.x, velocity.z).length() > 1.0:
		view_direction = Vector3(velocity.x, 0, velocity.z).normalized()
	if landing_view and not putting and not in_motion and not hole_complete and not landing_prediction.is_empty():
		var target: Vector3 = landing_prediction.position
		camera.position = camera.position.lerp(target - view_direction * 18.0 + Vector3.UP * 22.0, minf(delta * 5.0, 1.0))
		camera.look_at(target)
		_update_hud()
		return
	var following_bounce := in_motion and has_landed and not putting
	var target_camera := ball_position - view_direction * (1.4 if putting else 12.0) + Vector3.UP * (0.65 if putting else 7.0)
	if following_bounce:
		# Follow the ground rather than the ball vertically so the bounce stays visible.
		var ground_y := _ground_height(ball_position.x, ball_position.z)
		target_camera = Vector3(ball_position.x, ground_y, ball_position.z) - view_direction * 8.0 + Vector3.UP * 4.0
	camera.position = camera.position.lerp(target_camera, minf(delta * (8.0 if putting else (5.0 if following_bounce else 3.0)), 1.0))
	var look_target := ball_position + view_direction * (2.5 if following_bounce else (1.0 if putting else 6.0)) + Vector3.UP * (0.04 if putting else 0.5)
	camera.look_at(look_target)
	_update_hud()

func _say(text: String, toast_title: String, toast_detail: String = "", alert: bool = false) -> void:
	message = text
	hud_state.toast_serial += 1
	hud_state.toast_title = toast_title
	hud_state.toast_detail = toast_detail
	hud_state.toast_kind = HudState.ToastKind.ALERT if alert else HudState.ToastKind.NEUTRAL

# A new serial with an empty title tells the toast panel to dismiss immediately.
func _clear_toast() -> void:
	hud_state.toast_serial += 1
	hud_state.toast_title = ""
	hud_state.toast_detail = ""
	hud_state.toast_kind = HudState.ToastKind.NEUTRAL

func _putt_suggested_power(forward: Vector2) -> float:
	var slope := _ground_slope(ball_position)
	var green_resistance: float = STIMP_LAUNCH_SPEED * STIMP_LAUNCH_SPEED / (2.0 * GREEN_SPEEDS[green_speed_index] * 0.3048)
	var effective_drag := maxf(0.1, green_resistance + GRAVITY * GREEN_SLOPE_FACTOR * slope.dot(forward))
	var suggested := pow(sqrt(2.0 * effective_drag * _distance_to_cup(ball_position)) / maxf(float(CLUBS[club_index].speed) * _lie_factor(ball_position) * PUTTER_ROLL_SPEED_FACTOR, 0.01), 1.0 / PUTTER_POWER_EXPONENT)
	return clampf(suggested, 0.0, 1.0)

# Push raw game values to the HUD; components do all formatting.
func _update_hud() -> void:
	var s := hud_state
	var putting := club_index == CLUBS.size() - 1
	var heading := deg_to_rad(aim)
	var forward := Vector2(sin(heading), -cos(heading))
	var side := Vector2(cos(heading), sin(heading))
	var wind := _wind_velocity()
	var wind2 := Vector2(wind.x, wind.z) / MPH_TO_MPS
	s.hole_index = hole_index
	s.hole_yards = _selected_tee_yards()
	s.tee_name = _selected_tee_name()
	s.hole_scores = PackedInt32Array(hole_scores)
	s.strokes = strokes
	s.hole_complete = hole_complete
	s.has_next_hole = hole_index + 1 < HOLES.size()
	s.putting = putting
	s.on_green = _on_green(ball_position)
	s.in_motion = in_motion
	s.airborne = airborne
	s.has_landed = has_landed
	s.lie = _lie(ball_position)
	s.shot_lie = shot_lie
	s.lie_factor = _lie_factor(ball_position)
	s.distance_to_pin_m = _distance_to_cup(ball_position)
	s.shot_distance_m = Vector2(ball_position.x - shot_start.x, ball_position.z - shot_start.z).length()
	s.aim_degrees = aim
	s.carry_m = carry
	s.roll_m = roll_distance
	s.backspin_rpm = backspin_rpm
	s.sidespin_rpm = sidespin_rpm
	s.wind_mph = WIND_SPEEDS_MPH[wind_index]
	s.wind_toward_target_mph = wind2.dot(forward)
	s.wind_toward_right_mph = wind2.dot(side)
	s.club_name = CLUBS[club_index].name
	s.club_index = club_index
	s.recommended_club_index = recommended_club
	s.recommended_name = CLUBS[recommended_club].name if recommended_club >= 0 else ""
	s.recommended_yards = recommended_yards
	s.shape_index = shape_index
	s.type_index = shot_type_index
	s.spin_index = spin_index
	s.swing_speed_mph = swing_speed_mph
	s.stimp_index = green_speed_index
	var slope := _ground_slope(ball_position)
	s.slope_forward_percent = slope.dot(forward) * 100.0
	s.slope_right_percent = slope.dot(side) * 100.0
	var to_cup := Vector2(CUP.x - ball_position.x, CUP.z - ball_position.z)
	var cup_heading := rad_to_deg(atan2(to_cup.x, -to_cup.y))
	var aim_offset := wrapf(aim - cup_heading, -180.0, 180.0)
	s.putt_aim_degrees = aim_offset
	s.putt_aim_offset_inches = tan(deg_to_rad(aim_offset)) * to_cup.length() * 39.3701 if absf(aim_offset) < 80.0 else NAN
	s.putt_previous_valid = shot_lie == "Green" and strokes > 0
	s.putt_start_distance_m = Vector2(shot_start.x - CUP.x, shot_start.z - CUP.z).length()
	s.swing_active = swing_active
	s.backswing_valid = backswing >= MIN_BACKSWING
	s.power_locked = forward_distance >= FORWARD_TO_HIT
	s.backswing_power = _estimated_power()
	s.last_power = last_power
	s.swipe_degrees = _swipe_direction() if swing_active else 0.0
	s.last_swipe_degrees = last_direction
	s.swipe_sensitivity = swipe_sensitivity
	s.suggested_power = _putt_suggested_power(forward) if putting and not in_motion else -1.0
	s.preview_kind = HudState.PreviewKind.NONE
	if landing_view and not in_motion and not hole_complete and not landing_prediction.is_empty():
		var landing_pos: Vector3 = landing_prediction.position
		var travelled := Vector2(landing_pos.x - ball_position.x, landing_pos.z - ball_position.z).length()
		s.preview_kind = HudState.PreviewKind.PUTT if landing_prediction.putt else HudState.PreviewKind.LANDING
		s.preview_distance_m = travelled
		s.preview_roll_m = travelled
		s.preview_surface = landing_prediction.lie
		s.preview_tree_hit = landing_prediction.tree_hit
		s.preview_holed = landing_prediction.holed
		s.preview_power = landing_prediction.power
		s.preview_past_cup_m = landing_prediction.get("past_cup", 0.0)
		s.preview_lateral_cup_m = landing_prediction.get("lateral_cup", 0.0)
	hud.apply_state(s)
