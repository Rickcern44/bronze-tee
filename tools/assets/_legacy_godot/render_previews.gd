## Renders review previews from manifest.json. MUST run WINDOWED (no --headless): viewport capture needs a renderer.
##   assets/models/_previews/<family>.png for every family (1600x900), plus autumn_trees.png when trees use autumn.
## Each family is laid out in a row on a flat grass plane with a 1.8 m white reference post on the left.
## Run: perl -e 'alarm 300; exec @ARGV' /Users/rickcerny/Downloads/Godot_mono.app/Contents/MacOS/Godot --path /Users/rickcerny/dev/sandbox/bronze-tee --script res://tools/assets/render_previews.gd
extends SceneTree

const IMG_W: int = 1600
const IMG_H: int = 900
const GROUND_HEX: String = "#5AAD38"
const SKY_HEX: String = "#BFE3F5"
const GAP: float = 1.5
const POST_X: float = -1.2


func _init() -> void:
	_run()


func _run() -> void:
	var code: int = await _main()
	quit(code)


func _main() -> int:
	var manifest: Dictionary = AssetKit.read_manifest()
	if manifest.is_empty():
		print("FAIL: manifest missing or invalid, run build_all first")
		return 1
	var preview_dir: String = AssetKit.to_global(AssetKit.PREVIEW_DIR)
	var err: Error = AssetKit.ensure_dir(preview_dir)
	if err != OK:
		print("FAIL: cannot create %s" % preview_dir)
		return 1
	_ensure_gdignore(preview_dir)

	var by_family: Dictionary = {}
	for e in manifest.get("assets", []):
		var fam: String = String((e as Dictionary).get("family", "misc"))
		if not by_family.has(fam):
			by_family[fam] = []
		(by_family[fam] as Array).append(e)
	var families: Array = by_family.keys()
	families.sort()

	var failed: int = 0
	for fam in families:
		var ok: bool = await _render(by_family[fam], "", preview_dir.path_join(String(fam) + ".png"))
		if not ok:
			failed += 1

	var autumn: Array = []
	for e in by_family.get("trees", []):
		var palettes: Array = (e as Dictionary).get("variation", {}).get("palettes", [])
		if palettes.has("autumn"):
			autumn.append(e)
	if not autumn.is_empty():
		var ok_autumn: bool = await _render(autumn, AssetKit.PALETTE_AUTUMN, preview_dir.path_join("autumn_trees.png"))
		if not ok_autumn:
			failed += 1

	if failed == 0:
		print("render_previews: OK (%d families)" % families.size())
		return 0
	print("render_previews: FAILED %d" % failed)
	return 1


func _render(entries: Array, override_palette: String, out_path: String) -> bool:
	var sub := SubViewport.new()
	sub.size = Vector2i(IMG_W, IMG_H)
	sub.own_world_3d = true
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(sub)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(SKY_HEX)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 1.1
	sub.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	ground.mesh = plane
	ground.material_override = _plain_material(Color(GROUND_HEX))
	sub.add_child(ground)

	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.08, 1.8, 0.08)
	post.mesh = post_mesh
	post.material_override = _plain_material(Color.WHITE)
	post.position = Vector3(POST_X, 0.9, 0.0)
	sub.add_child(post)

	var content := Node3D.new()
	sub.add_child(content)
	var x: float = 0.0
	var max_h: float = 1.8
	for e in entries:
		var file: String = String((e as Dictionary).get("file", ""))
		var scene: Node3D = AssetKit.load_glb_scene(file)
		if scene == null:
			print("FAIL: cannot load %s" % file)
			_discard(sub)
			return false
		var bounds: AABB = AssetKit.mesh_bounds(scene)
		scene.position = Vector3(x - bounds.position.x, 0.0, -(bounds.position.z + bounds.size.z * 0.5))
		content.add_child(scene)
		for item in AssetKit.flatten_meshes(scene):
			var mi: MeshInstance3D = item["node"]
			if override_palette != "":
				mi.material_override = AssetKit.make_material(override_palette)
			else:
				var mat := mi.get_active_material(0) as BaseMaterial3D
				if mat != null:
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		max_h = maxf(max_h, bounds.end.y)
		x += maxf(bounds.size.x, 0.5) + GAP

	var row_end: float = maxf(x - GAP, 0.0)
	var centre: Vector3 = Vector3((POST_X + row_end) * 0.5, max_h * 0.4, 0.0)
	var span: float = row_end - POST_X + 2.0
	var dist: float = maxf(span * 0.95, maxf(max_h * 2.6, 7.0))
	var cam := Camera3D.new()
	cam.fov = 35.0
	sub.add_child(cam)
	cam.current = true
	cam.look_at_from_position(centre + Vector3(0.35, 0.35, 1.0).normalized() * dist, centre, Vector3.UP)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	if img == null:
		print("FAIL: no image captured. Run render_previews windowed, not with --headless")
		_discard(sub)
		return false
	var save_err: Error = img.save_png(out_path)
	_discard(sub)
	if save_err != OK:
		print("FAIL: cannot save %s" % out_path)
		return false
	print("preview: %s (%d assets)" % [out_path, entries.size()])
	return true


func _discard(sub: SubViewport) -> void:
	get_root().remove_child(sub)
	sub.free()


func _plain_material(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	return mat


func _ensure_gdignore(preview_dir: String) -> void:
	var path: String = preview_dir.path_join(".gdignore")
	if FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.close()
