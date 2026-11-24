extends SceneTree
# Surface-map rendering playtest (RCE-178): loads the mapped fixture hole
# (tests/fixtures/surface_map_hole.tres, baked by make_surface_map_fixture.py),
# renders it top-down and checks the terrain shader's use_surface_map palette
# against _surface_at in scripts/main.gd by sampling the viewport.
# Run: ./tools/playtest.sh surface_map
# Screenshots: playtest-output/surface_map/ (gitignored).
#
# How lighting is handled
# -----------------------
# The colour checks run on an "albedo" render: a runtime copy of
# shaders/terrain.gdshader with exactly two edits, `diffuse_burley` ->
# `unshaded` and `TIME` -> `0.0` (step 1 fails if either edit does not apply
# exactly). Every uniform and the whole use_surface_map branch are the shader
# under test, so the framebuffer holds ALBEDO = palette * albedo_gain, with the
# water scroll frozen. The expected colour of every pixel is computed on the
# CPU from the same textures and uniforms: palette[_surface_at(x, z)] at that
# pixel's world position. Sampled and expected colours are averaged over a
# window (or a 0.1 m strip for boundaries), which removes per-texel noise
# without hiding a wrong texture or a wrong ID.
# Colour space: with this project's Compatibility renderer, the unshaded output
# is albedo_gain times the stored (sRGB-encoded) texel values, with no transfer
# function on input or output. Constants such as the bunker sand, bank_color
# and shallow_color also pass through unchanged. All comparisons are therefore
# in display values, the space the shader blends in.
# A second pass renders the real, lit shader. On this almost flat terrain,
# lighting acts as one affine transform per channel (sun and ambient scale,
# plus a small specular and ambient offset). That transform is fitted over the
# dry windows; each lit window must match the fit and still classify as its own
# surface. Water is checked by classification only, because its roughness and
# specular differ.
#
# Tolerances (display values 0..1, per channel)
# ---------------------------------------------
# Albedo: |sampled - expected| <= 0.004 + 4% of expected. 0.004 is one 8-bit
# output step (1/255). The 4% covers GPU filtering against CPU sampling. The
# terrain textures are imported with mipmaps and sampled with
# filter_linear_mipmap_anisotropic; in a 16 m window view one pixel covers about
# 2.8 texels of a 512 px, 4 m tile, so the GPU reads a filtered average from
# mip level 1-2, while the CPU reads one base-level texel per pixel. Mip levels
# are box-filtered, so both have the same mean over a window; the difference is
# sampling noise of the sparse CPU texels. The largest observed error is deep rough red,
# 0.0067 (4.6%) against a limit of 0.0098. Adjacent palette entries are further
# apart (fairway light vs first cut differ by about 0.03 in R and G), and
# every window must also be nearest to its own palette entry. The tolerance
# therefore cannot absorb a swapped texture or ID.
# Lit: |sampled - fitted| <= 0.008 + 3% of fitted; the largest observed
# residual is 0.0035.
# Boundaries: the blend fit uses the albedo tolerance; the fitted mix share
# may step back by at most 0.05 (MONOTONIC_SLACK); the green/collar blend
# must cross 50% within half a .srf sample (one 0.25 m strip step) of where
# _surface_at changes; and 0.05 m probes at 1/4 and 3/4 of the way between the
# last green and first collar sample must fit t within 0.15 of 0.25 and 0.75
# (what bilinear blending predicts), strictly inside (0.1, 0.9) and increasing.

const OUT_DIR := "playtest-output/surface_map"
const FIXTURE := "res://tests/fixtures/surface_map_hole.tres"
const SHOT_W := 1280
const SHOT_H := 720
const MIN_DISTINCT_COLOURS := 50
const CAMERA_HEIGHT := 50.0
const ALBEDO_ABS_TOL := 0.004
const ALBEDO_REL_TOL := 0.04
const LIT_ABS_TOL := 0.008
const LIT_REL_TOL := 0.03
const MONOTONIC_SLACK := 0.05
# Fitted bank share allowed beyond bank_width. The deep-rough-to-bank axis is
# short (about 0.07 per channel), so the 4-5% deep rough red offset (see
# the tolerance notes) reads as a share of about 0.05 there.
const BANK_FAR_SHARE := 0.1

var failures := 0
var game
var camera: Camera3D
var material: ShaderMaterial
var real_shader: Shader
var albedo_shader: Shader
var images := {}
var S: Dictionary
var gain := 0.75
var step_shadow := 0.3
var shallow_col := Color()
var shallow_strength := 0.55
var bank_col := Color()
var bank_strength := 0.5
var bank_width := 1.2
# Mean colour of each palette entry over one full texture tile, for
# nearest-palette classification.
var palette_means := {}

# Interior windows: label, expected Surface key, centre (x, z), half size (x, z).
# Each window sits >= 0.5 m inside its surface on the .srf grid, so the
# shader's step shadow and bilinear ID blend do not reach it. Grass windows
# span one 4 m tile; fairway windows sit inside one 12 m mow band.
var windows := [
	["green", "GREEN", Vector2(-4, -92), Vector2(2, 2)],
	["fairway_light_band", "FAIRWAY", Vector2(0, -30), Vector2(2, 2)],
	["fairway_dark_band", "FAIRWAY", Vector2(0, -42), Vector2(2, 2)],
	["first_cut", "FIRST_CUT", Vector2(11.75, -50), Vector2(0.75, 2)],
	["second_cut", "SECOND_CUT", Vector2(16.25, -50), Vector2(1.75, 2)],
	["deep_rough", "DEEP_ROUGH", Vector2(-20, -100), Vector2(2, 2)],
	["water", "WATER", Vector2(-31, -45), Vector2(2.5, 3)],
	["path", "PATH", Vector2(29.25, -50), Vector2(1.0, 2)],
	["tee", "TEE", Vector2(0, 0), Vector2(2, 2)],
	["bunker", "BUNKER", Vector2(16, -86), Vector2(2, 1.2)],
]


func _initialize() -> void:
	call_deferred("run")


func wait(n: int) -> void:
	for i in n:
		await process_frame


func step(n: int, ok: bool, text: String) -> void:
	if ok:
		print("PASS step %d: %s" % [n, text])
	else:
		print("FAIL step %d: %s" % [n, text])
		failures += 1


func hex(c: Color) -> String:
	return "#" + c.to_html(false)


func fmt(c: Color) -> String:
	return "%s (%.4f, %.4f, %.4f)" % [hex(c), c.r, c.g, c.b]


func v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func col(v: Vector3) -> Color:
	return Color(v.x, v.y, v.z)


# Per-channel tolerance check (display values).
func within(sampled: Color, expected: Color, abs_tol: float, rel_tol: float) -> bool:
	for i in 3:
		if absf(sampled[i] - expected[i]) > abs_tol + rel_tol * absf(expected[i]):
			return false
	return true


func max_error(sampled: Color, expected: Color) -> float:
	return maxf(maxf(absf(sampled.r - expected.r), absf(sampled.g - expected.g)), absf(sampled.b - expected.b))


# A shader uniform as set by main.gd, or the shader default when main.gd does
# not set it.
func param(name: String) -> Variant:
	var value: Variant = material.get_shader_parameter(name)
	if value == null:
		value = RenderingServer.shader_get_parameter_default(real_shader.get_rid(), name)
	return value


# ---------------------------------------------------------------------------
# CPU reference of the use_surface_map palette (display values, before shadow).

func texel(name: String, uv: Vector2) -> Color:
	var img: Image = images[name]
	var w := img.get_width()
	var h := img.get_height()
	var x := posmod(int(floor(uv.x * w)), w)
	var y := posmod(int(floor(uv.y * h)), h)
	return img.get_pixel(x, y)


# palette[id] from terrain.gdshader at world (x, z), interior (shadow = 1,
# no shallow band), multiplied by albedo_gain. Water uses TIME = 0.
func palette(id: int, p: Vector2) -> Color:
	var guv := p / float(param("grass_tile"))
	var c := Color(1, 0, 1)
	if id == S.DEEP_ROUGH: c = texel("deep_rough_texture", guv)
	elif id == S.SECOND_CUT: c = texel("second_cut_texture", guv)
	elif id == S.FIRST_CUT: c = texel("first_cut_texture", guv)
	elif id == S.FAIRWAY:
		var wave := sin(TAU * (-p.y / float(param("mow_band_length"))))
		c = texel("fairway_dark_texture" if wave < 0.0 else "fairway_light_texture", guv)
	elif id == S.GREEN: c = texel("green_texture", guv)
	elif id == S.COLLAR: c = texel("collar_texture", guv)
	elif id == S.TEE: c = texel("fairway_light_texture", guv)
	elif id == S.PATH:
		var path_width: float = float(param("path_half_width")) * 2.0
		var path_x: float = float(param("path_center_x")) + float(param("path_sway")) * sin(p.y * float(param("path_sway_frequency"))) + game._fairway_dogleg_shift(p.y)
		c = texel("path_texture", Vector2((p.x - path_x) / path_width + 0.5, p.y / path_width))
	elif id == S.WATER:
		var wuv := p / float(param("water_tile"))
		var a := texel("water_texture", wuv)
		var b := texel("water_texture", wuv * 1.17 + Vector2(0.37, 0.61))
		c = Color((a.r + b.r) * 0.5, (a.g + b.g) * 0.5, (a.b + b.b) * 0.5)
	elif id == S.BUNKER: c = Color(0.66, 0.59, 0.43)
	return Color(c.r * gain, c.g * gain, c.b * gain)


func full_tile_mean(name: String) -> Color:
	var img: Image = images[name]
	var sum := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			sum += v3(img.get_pixel(x, y))
			n += 1
	return col(sum / float(n) * gain)


# ---------------------------------------------------------------------------
# Rendering and sampling.

func view(centre: Vector2, size: float) -> void:
	var y: float = game._ground_height(centre.x, centre.y) + CAMERA_HEIGHT
	camera.size = size
	# Screen up is -Z (toward the cup), screen right is +X.
	camera.look_at_from_position(Vector3(centre.x, y, centre.y), Vector3(centre.x, y - 1.0, centre.y), Vector3(0, 0, -1))


func render(name: String) -> Image:
	await wait(2)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + name + ".png")
	return img


func valid(img: Image, name: String) -> bool:
	if not FileAccess.file_exists(OUT_DIR + "/" + name + ".png"):
		return false
	if img.get_width() != SHOT_W or img.get_height() != SHOT_H:
		return false
	var colours := {}
	for gy in 18:
		for gx in 32:
			colours[img.get_pixel(int((gx + 0.5) * SHOT_W / 32.0), int((gy + 0.5) * SHOT_H / 18.0)).to_html(false)] = true
	return colours.size() >= MIN_DISTINCT_COLOURS


# Screen rect of a world rect (x0..x1, z0..z1), projected with the camera and
# inset by one pixel.
func screen_rect(x0: float, x1: float, z0: float, z1: float) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for x in [x0, x1]:
		for z in [z0, z1]:
			var s: Vector2 = camera.unproject_position(Vector3(x, game._ground_height(x, z), z))
			lo = lo.min(s)
			hi = hi.max(s)
	var a := Vector2i(ceili(lo.x) + 1, ceili(lo.y) + 1)
	var b := Vector2i(floori(hi.x) - 1, floori(hi.y) - 1)
	return Rect2i(a, (b - a).max(Vector2i.ZERO))


func world_at(px: int, py: int) -> Vector2:
	var w: Vector3 = camera.project_position(Vector2(px + 0.5, py + 0.5), CAMERA_HEIGHT)
	return Vector2(w.x, w.z)


# Mean sampled colour over a screen rect, plus the CPU palette mean
# for each requested ID over the same pixels and the set of _surface_at IDs seen.
func measure(img: Image, rect: Rect2i, ids: Array, stride: int) -> Dictionary:
	var sum := Vector3.ZERO
	var ref := []
	for i in ids.size():
		ref.append(Vector3.ZERO)
	var seen := {}
	var n := 0
	for py in range(rect.position.y, rect.end.y + 1, stride):
		for px in range(rect.position.x, rect.end.x + 1, stride):
			sum += v3(img.get_pixel(px, py))
			var p := world_at(px, py)
			seen[game._surface_at(p.x, p.y)] = true
			for i in ids.size():
				ref[i] += v3(palette(ids[i], p))
			n += 1
	var refs := []
	for r in ref:
		refs.append(col(r / maxf(n, 1)))
	return {"sampled": col(sum / maxf(n, 1)), "refs": refs, "seen": seen.keys(), "count": n}


func nearest_label(c: Color, means: Dictionary) -> String:
	var best := ""
	var best_d := INF
	for label in means:
		var d := v3(c).distance_to(v3(means[label]))
		if d < best_d:
			best_d = d
			best = label
	return best


func palette_label(key: String, centre: Vector2) -> String:
	match key:
		"FAIRWAY": return "fairway_dark" if sin(TAU * (-centre.y / float(param("mow_band_length")))) < 0.0 else "fairway_light"
		"TEE": return "fairway_light"
	return key.to_lower()


# Best fit of c to s * mix(a, b, t) with t in [0, 1] and s in the step-shadow
# range [1 - step_shadow, 1]. Returns t, s, the fitted colour and whether c is
# within tolerance of it (no foreign colour).
func blend_fit(c: Color, a: Color, b: Color) -> Dictionary:
	var best := {"t": 0.0, "s": 1.0, "fit": a, "err": INF}
	for i in 101:
		var t := i / 100.0
		var m := v3(a).lerp(v3(b), t)
		var s := clampf(v3(c).dot(m) / maxf(m.dot(m), 1e-9), 1.0 - step_shadow - 0.02, 1.02)
		var fit := col(m * s)
		var err := max_error(c, fit)
		if err < best.err:
			best = {"t": t, "s": s, "fit": fit, "err": err}
	best["ok"] = within(c, best.fit, ALBEDO_ABS_TOL, ALBEDO_REL_TOL)
	return best


# Projection of c onto the segment a -> b: c = mix(a, b, k).
func line_fit(c: Color, a: Color, b: Color) -> Dictionary:
	var d := v3(b) - v3(a)
	var k := (v3(c) - v3(a)).dot(d) / maxf(d.dot(d), 1e-9)
	var fit := col(v3(a) + d * k)
	return {"k": k, "fit": fit, "ok": within(c, fit, ALBEDO_ABS_TOL, ALBEDO_REL_TOL)}


# Strip rect: a narrow column at x (width w metres) over z0..z1.
func strip(x: float, w: float, z0: float, z1: float) -> Rect2i:
	return screen_rect(x - w * 0.5, x + w * 0.5, z0, z1)


# IDs of the four .srf samples the shader blends at (x, z).
func corner_ids(x: float, z: float) -> Array:
	var origin: Vector2 = game.active_hole.surface_map_origin
	var spacing: float = game.active_hole.surface_map_spacing
	var gx := floorf((x - origin.x) / spacing)
	var gz := floorf((origin.y - z) / spacing)
	var out := []
	for d in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		out.append(game._surface_at(origin.x + (gx + d.x) * spacing, origin.y - (gz + d.y) * spacing))
	return out


# ---------------------------------------------------------------------------

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await wait(2)
	S = game.Surface

	# Step 1: load the mapped fixture hole and isolate the terrain.
	game.HOLES.append(load(FIXTURE))
	game._load_hole(game.HOLES.size() - 1)
	await wait(2)
	# Freeze gameplay so nothing moves the camera or toggles visibility, then
	# hide everything but the terrain, the sun and the environment.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for child in game.get_children():
		if child is CanvasLayer:
			child.visible = false
		elif child is Node3D and not child is Light3D and child.name != "CourseTerrain":
			child.visible = false
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	camera.far = 200.0
	root.add_child(camera)
	camera.make_current()
	material = game.terrain_material
	real_shader = material.shader
	var code: String = real_shader.code
	var lit_mode := "render_mode cull_disabled, diffuse_burley;"
	var edits_ok := code.count(lit_mode) == 1 and code.count("TIME") == 2
	albedo_shader = Shader.new()
	albedo_shader.code = code.replace(lit_mode, "render_mode cull_disabled, unshaded;").replace("TIME", "0.0")
	for name in game.TERRAIN_TEXTURES:
		var img: Image = load(game.TERRAIN_TEXTURES[name]).get_image()
		if img.is_compressed():
			img.decompress()
		images[name] = img
	gain = float(param("albedo_gain"))
	step_shadow = float(param("step_shadow"))
	shallow_col = (param("shallow_color") as Color)
	shallow_strength = float(param("shallow_strength"))
	bank_col = (param("bank_color") as Color)
	bank_strength = float(param("bank_strength"))
	bank_width = float(param("bank_width"))
	palette_means = {
		"deep_rough": full_tile_mean("deep_rough_texture"),
		"second_cut": full_tile_mean("second_cut_texture"),
		"first_cut": full_tile_mean("first_cut_texture"),
		"fairway_light": full_tile_mean("fairway_light_texture"),
		"fairway_dark": full_tile_mean("fairway_dark_texture"),
		"green": full_tile_mean("green_texture"),
		"path": full_tile_mean("path_texture"),
		"water": full_tile_mean("water_texture"),
		"bunker": Color(0.66 * gain, 0.59 * gain, 0.43 * gain),
	}
	var mapped: bool = game.surface_map != null and material.get_shader_parameter("use_surface_map") == true
	step(1, mapped and edits_ok and game.active_hole.resource_path == FIXTURE,
		"fixture hole %s loaded with surface map %s, use_surface_map=%s; albedo shader copy edits found=%s" % [
			FIXTURE, str(game.surface_map.get_size() if game.surface_map else null), str(material.get_shader_parameter("use_surface_map")), str(edits_ok)])

	# Overview screenshots (artifacts): lit game render and albedo render.
	view(Vector2(0, -45), 140.0)
	var overview_lit := await render("01_overview_lit")
	material.shader = albedo_shader
	var overview_albedo := await render("02_overview_albedo")
	var params_kept: bool = material.get_shader_parameter("use_surface_map") == true and material.get_shader_parameter("surface_ids") != null

	# Step 2: interior windows, albedo pass.
	var albedo_samples := {}
	var ok2 := params_kept
	var lines2 := []
	for w in windows:
		var label: String = w[0]
		var id: int = S[w[1]]
		var c: Vector2 = w[2]
		var h: Vector2 = w[3]
		view(c, 16.0)
		var img := await render("albedo_" + label)
		var m := measure(img, screen_rect(c.x - h.x, c.x + h.x, c.y - h.y, c.y + h.y), [id], 2)
		var sampled: Color = m.sampled
		var expected: Color = m.refs[0]
		var ids_ok: bool = m.seen == [id]
		var tol_ok := within(sampled, expected, ALBEDO_ABS_TOL, ALBEDO_REL_TOL)
		var nearest := nearest_label(sampled, palette_means)
		var class_ok := nearest == palette_label(w[1], c)
		albedo_samples[label] = [sampled, expected]
		var ok: bool = ids_ok and tol_ok and class_ok and m.count > 100
		ok2 = ok2 and ok
		lines2.append("  %s %s at (%.2f, %.2f): sampled %s expected %s max err %.4f, _surface_at ids %s, nearest palette %s, %d px%s" % [
			"ok  " if ok else "BAD ", label, c.x, c.y, fmt(sampled), fmt(expected), max_error(sampled, expected), str(m.seen), nearest, m.count,
			"" if ok else " <-- MISMATCH"])
	step(2, ok2, "albedo palette matches palette[_surface_at] in %d windows (shader params kept after swap: %s)\n%s" % [windows.size(), str(params_kept), "\n".join(lines2)])

	# Step 3: green -> collar boundary. Strips across x at z -91..-93, where the
	# .srf green ends at x 11.5 and the collar runs 12.0..13.0.
	view(Vector2(11.5, -92), 8.0)
	var img3 := await render("albedo_green_boundary")
	var ok3 := true
	var lines3 := []
	var prev_t := -1.0
	var cross_x := INF
	var surface_change_x := INF
	var prev_surface := -1
	var x := 9.5
	while x <= 12.751:
		var m := measure(img3, strip(x, 0.1, -91.0, -93.0), [S.GREEN, S.COLLAR], 1)
		var fit := blend_fit(m.sampled, m.refs[0], m.refs[1])
		var mono: bool = fit.t >= prev_t - MONOTONIC_SLACK
		var surface: int = game._surface_at(x, -92.0)
		if prev_surface == S.GREEN and surface == S.COLLAR and surface_change_x == INF:
			surface_change_x = x
		prev_surface = surface
		if fit.t >= 0.5 and cross_x == INF:
			cross_x = x
		var ok: bool = fit.ok and mono
		ok3 = ok3 and ok
		lines3.append("  %s x %.2f: sampled %s fit %s (t %.2f toward collar, shade %.2f) _surface_at %d%s" % [
			"ok  " if ok else "BAD ", x, fmt(m.sampled), fmt(fit.fit), fit.t, fit.s, surface, "" if ok else " <-- foreign colour or non-monotonic"])
		prev_t = maxf(prev_t, fit.t)
		x += 0.25
	var spacing: float = game.active_hole.surface_map_spacing
	var cross_ok: bool = absf(cross_x - surface_change_x) <= spacing * 0.5 + 0.01
	ok3 = ok3 and cross_ok
	# Sub-sample probes. The 0.25 m strips above cannot tell a bilinear blend
	# from a hard edge: the only strip between the two colours sits on the
	# _surface_at switch (the midpoint between .srf samples, since _surface_at
	# rounds to the nearest sample), where a hard edge also averages to about
	# 0.5. Between the last green sample x_g and the first collar sample
	# x_g + spacing, the shader mixes the two palette colours with
	# fraction.x = (x - x_g) / spacing, so a narrow strip centred at
	# x_g + f * spacing must fit t = f (the strip mean of a linear ramp is its
	# centre value). A hard edge at the midpoint gives t = 0 below it and 1 above
# (checked by patching fraction to step(0.5, ...): probes fit t 0.05 and 1.00).
# Observed t is 0.33 and 0.85: the fitted t reads about +0.08 high across the
# whole edge (also at x 11.50 and 11.75), because the CPU collar reference sits
# slightly bluer than the render (interior collar strips fit at the t = 1 clamp).
	var origin_x: float = game.active_hole.surface_map_origin.x
	var x_g := INF
	var col_i := ceili((9.5 - origin_x) / spacing)
	while origin_x + col_i * spacing <= 12.75:
		var sx := origin_x + col_i * spacing
		if game._surface_at(sx, -92.0) == S.GREEN and game._surface_at(sx + spacing, -92.0) == S.COLLAR:
			x_g = sx
			break
		col_i += 1
	# Every .srf row the probes touch must have the same green | collar column
	# pair, so the z blend between rows cannot mix in a third colour.
	var rows_ok := x_g != INF
	var row_z := -91.0
	while rows_ok and row_z >= -93.0 - spacing:
		rows_ok = game._surface_at(x_g, row_z) == S.GREEN and game._surface_at(x_g + spacing, row_z) == S.COLLAR
		row_z -= spacing
	var probe_ok := rows_ok
	var probe_lines := []
	var probe_t := []
	for f in [0.25, 0.75]:
		var px: float = x_g + f * spacing
		var m := measure(img3, strip(px, 0.05, -91.0, -93.0), [S.GREEN, S.COLLAR], 1)
		var fit := blend_fit(m.sampled, m.refs[0], m.refs[1])
		var ok: bool = fit.ok and fit.t > 0.1 and fit.t < 0.9 and absf(fit.t - f) <= 0.15 and m.count > 50
		probe_ok = probe_ok and ok
		probe_t.append(fit.t)
		probe_lines.append("  %s probe x %.3f (0.05 m, %d px): sampled %s fit %s t %.2f, bilinear predicts %.2f +/- 0.15, must be in (0.1, 0.9)%s" % [
			"ok  " if ok else "BAD ", px, m.count, fmt(m.sampled), fmt(fit.fit), fit.t, f, "" if ok else " <-- hard edge or wrong blend"])
	probe_ok = probe_ok and probe_t.size() == 2 and probe_t[0] < probe_t[1]
	ok3 = ok3 and probe_ok
	step(3, ok3, "green->collar blend stays between the two palette colours (with step shadow), is monotonic, and crosses at x %.2f where _surface_at changes at x %.2f; sub-sample probes between samples x %.2f | %.2f blend bilinearly (rows consistent: %s, increasing: %s)\n%s\n%s" % [
		cross_x, surface_change_x, x_g, x_g + spacing, str(rows_ok), str(probe_t.size() == 2 and probe_t[0] < probe_t[1]), "\n".join(lines3), "\n".join(probe_lines)])

	# Step 4: fairway -> first cut edge in the light mow band (x 10 | 10.5).
	# These textures are nearly parallel in RGB, so only the hull check is
	# meaningful here: every strip must be a shaded mix of the two neighbours.
	view(Vector2(10.25, -30), 8.0)
	var img4 := await render("albedo_fairway_edge")
	var ok4 := true
	var lines4 := []
	x = 8.5
	while x <= 12.001:
		var m := measure(img4, strip(x, 0.1, -28.0, -32.0), [S.FAIRWAY, S.FIRST_CUT], 1)
		var fit := blend_fit(m.sampled, m.refs[0], m.refs[1])
		ok4 = ok4 and fit.ok
		lines4.append("  %s x %.2f: sampled %s fit %s (t %.2f, shade %.2f) _surface_at %d%s" % [
			"ok  " if fit.ok else "BAD ", x, fmt(m.sampled), fmt(fit.fit), fit.t, fit.s, game._surface_at(x, -30.0), "" if fit.ok else " <-- foreign colour"])
		x += 0.25
	# The interior ends are the unshaded palette colours.
	var end_a := measure(img4, strip(8.5, 0.1, -28.0, -32.0), [S.FAIRWAY], 1)
	var end_b := measure(img4, strip(12.0, 0.1, -28.0, -32.0), [S.FIRST_CUT], 1)
	var ends_ok := within(end_a.sampled, end_a.refs[0], ALBEDO_ABS_TOL, ALBEDO_REL_TOL) and within(end_b.sampled, end_b.refs[0], ALBEDO_ABS_TOL, ALBEDO_REL_TOL)
	ok4 = ok4 and ends_ok
	step(4, ok4, "fairway->first cut edge is a shaded blend of the two palette colours; ends match (%s)\n%s" % [str(ends_ok), "\n".join(lines4)])

	# Step 5: water bank. The .srf water ends at x -26.0; dry ground (deep
	# rough) starts at -25.5. Water strips must be mix(water, shallow) with the
	# shallow share rising toward the edge; dry strips mix(deep rough, bank) with
	# the bank share falling away from it; strips that straddle the edge must lie
	# between their neighbours.
	view(Vector2(-26, -46), 12.0)
	var img5 := await render("albedo_water_bank")
	var ok5 := true
	var lines5 := []
	var strips5 := []
	# Strip centres sit between .srf sample columns (x = -40 + 0.5 n), so no
	# 0.1 m strip straddles a column and each one has a single zone.
	x = -29.125
	while x <= -23.0:
		var ids := corner_ids(x, -46.0)
		var zone := "mixed"
		if ids.all(func(i): return i == S.WATER): zone = "water"
		elif not ids.has(S.WATER): zone = "dry"
		var m := measure(img5, strip(x, 0.1, -42.0, -50.0), [S.WATER, S.DEEP_ROUGH], 1)
		strips5.append({"x": x, "zone": zone, "m": m})
		x += 0.25
	var prev_w := -INF
	var prev_k := INF
	var first_dry_k := -1.0
	var far_k_ok := true
	for i in strips5.size():
		var s: Dictionary = strips5[i]
		var m: Dictionary = s.m
		var ok := true
		var detail := ""
		if s.zone == "water":
			var fit := line_fit(m.sampled, m.refs[0], Color(shallow_col.r * gain, shallow_col.g * gain, shallow_col.b * gain))
			ok = fit.ok and fit.k >= -MONOTONIC_SLACK and fit.k <= shallow_strength + MONOTONIC_SLACK and fit.k >= prev_w - MONOTONIC_SLACK
			prev_w = maxf(prev_w, fit.k)
			detail = "fit %s shallow share %.2f" % [fmt(fit.fit), fit.k]
		elif s.zone == "dry":
			var fit := line_fit(m.sampled, m.refs[1], Color(bank_col.r * gain, bank_col.g * gain, bank_col.b * gain))
			ok = fit.ok and fit.k >= -MONOTONIC_SLACK and fit.k <= bank_strength + MONOTONIC_SLACK and fit.k <= prev_k + MONOTONIC_SLACK
			prev_k = minf(prev_k, fit.k)
			if first_dry_k < 0.0:
				first_dry_k = fit.k
			if s.x >= -26.0 + bank_width + 0.5 and fit.k > BANK_FAR_SHARE:
				far_k_ok = false
			detail = "fit %s bank share %.2f" % [fmt(fit.fit), fit.k]
		else:
			var lo: Color = strips5[maxi(i - 1, 0)].m.sampled
			var hi: Color = strips5[mini(i + 1, strips5.size() - 1)].m.sampled
			for ch in 3:
				var a := minf(lo[ch], hi[ch])
				var b := maxf(lo[ch], hi[ch])
				var t := ALBEDO_ABS_TOL + ALBEDO_REL_TOL * b
				if m.sampled[ch] < a - t or m.sampled[ch] > b + t:
					ok = false
			detail = "between neighbours %s and %s" % [hex(lo), hex(hi)]
		ok5 = ok5 and ok
		lines5.append("  %s x %.2f %s: sampled %s %s%s" % ["ok  " if ok else "BAD ", s.x, s.zone, fmt(m.sampled), detail, "" if ok else " <-- MISMATCH"])
	var bank_visible := first_dry_k >= 0.15
	ok5 = ok5 and bank_visible and far_k_ok and prev_w >= 0.15
	step(5, ok5, "water bank: shallow band and dark bank blend monotonically; shallow share at the edge %.2f (>= 0.15), bank share at the first dry strip %.2f (>= 0.15), bank gone beyond bank_width (%s)\n%s" % [
		prev_w, first_dry_k, str(far_k_ok), "\n".join(lines5)])

	# Step 6: lit pass with the real shader. Fit lit = K * albedo + O per channel
	# over the dry windows, then check each window against the fit and that it
	# still classifies as its own surface.
	material.shader = real_shader
	var lit_samples := {}
	for w in windows:
		var c: Vector2 = w[2]
		var h: Vector2 = w[3]
		view(c, 16.0)
		var img := await render("lit_" + w[0])
		lit_samples[w[0]] = measure(img, screen_rect(c.x - h.x, c.x + h.x, c.y - h.y, c.y + h.y), [], 2).sampled
	var dry := []
	for w in windows:
		if w[1] != "WATER":
			dry.append(w[0])
	var k := Vector3.ZERO
	var o := Vector3.ZERO
	for ch in 3:
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var sxy := 0.0
		for label in dry:
			var ax: float = albedo_samples[label][1][ch]
			var ly: float = lit_samples[label][ch]
			sx += ax
			sy += ly
			sxx += ax * ax
			sxy += ax * ly
		var n := float(dry.size())
		k[ch] = (n * sxy - sx * sy) / maxf(n * sxx - sx * sx, 1e-12)
		o[ch] = (sy - k[ch] * sx) / n
	var lit_means := {}
	for label in palette_means:
		lit_means[label] = col(v3(palette_means[label]) * k + o)
	var ok6 := k.x > 0.0 and k.y > 0.0 and k.z > 0.0
	var lines6 := []
	for w in windows:
		var label: String = w[0]
		var sampled: Color = lit_samples[label]
		var predicted := col(v3(albedo_samples[label][1]) * k + o)
		var nearest := nearest_label(sampled, lit_means)
		var class_ok := nearest == palette_label(w[1], w[2])
		var fit_ok: bool = w[1] == "WATER" or within(sampled, predicted, LIT_ABS_TOL, LIT_REL_TOL)
		var ok: bool = class_ok and fit_ok
		ok6 = ok6 and ok
		lines6.append("  %s %s: lit %s model %s nearest %s%s" % [
			"ok  " if ok else "BAD ", label, fmt(sampled), fmt(predicted) if w[1] != "WATER" else "(water: specular, class only)", nearest, "" if ok else " <-- MISMATCH"])
	step(6, ok6, "lit render: lighting model K=(%.3f, %.3f, %.3f) O=(%.4f, %.4f, %.4f) fits all dry windows; every window classifies as its own surface\n%s" % [
		k.x, k.y, k.z, o.x, o.y, o.z, "\n".join(lines6)])

	# Step 7: screenshots exist and are not blank.
	step(7, valid(overview_lit, "01_overview_lit") and valid(overview_albedo, "02_overview_albedo"),
		"overview screenshots saved under %s and valid" % OUT_DIR)

	step(8, failures == 0, "no earlier step failed")
	if failures > 0:
		print("SURFACE MAP PLAYTEST FAILED: %d step(s) failed; see BAD lines above" % failures)
	quit(0 if failures == 0 else 1)
