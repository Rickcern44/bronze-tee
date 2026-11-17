## Checks assets/models/manifest.json and every .glb it lists (headless):
##   - palettes exist and are 64x64, ids unique, manifest version 1
##   - each .glb exists, loads back via GLTFDocument, and its triangle count matches the manifest and the budget
##   - pivot: "base" (default) min.y within 0.02 of 0; "rim" max.y within 0.02 of 0; "sunk" min.y <= 0.02 and max.y >= 0.2
##   - collision: present unless visual_only; kind tree/cylinder/sphere with its fields; trees need "tree", flagstick needs "cylinder"
##   - every listed part name exists as a mesh node in the .glb
## Prints one line per asset, then PASS or FAIL <n>. Exit code 0 on PASS, 1 on FAIL.
## Run: perl -e 'alarm 300; exec @ARGV' /Users/rickcerny/Downloads/Godot_mono.app/Contents/MacOS/Godot --headless --path /Users/rickcerny/dev/sandbox/bronze-tee --script res://tools/assets/validate.gd
extends SceneTree

const PIVOT_TOLERANCE: float = 0.02


func _init() -> void:
	quit(_run())


func _run() -> int:
	var manifest: Dictionary = AssetKit.read_manifest()
	if manifest.is_empty():
		print("FAIL: manifest missing or invalid: %s" % AssetKit.to_global(AssetKit.manifest_path()))
		return 1
	var failures: int = 0
	if int(manifest.get("version", 0)) != 1:
		print("FAIL: manifest version is not 1")
		failures += 1

	for palette in [AssetKit.PALETTE_DEFAULT, AssetKit.PALETTE_AUTUMN]:
		var img: Image = Image.load_from_file(AssetKit.to_global(palette))
		if img == null or img.get_width() != 64 or img.get_height() != 64:
			print("FAIL: palette missing or not 64x64: %s" % palette)
			failures += 1

	var assets: Array = manifest.get("assets", [])
	var seen: Dictionary = {}
	for entry_value in assets:
		var problems: Array[String] = []
		var entry: Dictionary = entry_value
		var id: String = String(entry.get("id", ""))
		if id.is_empty():
			problems.append("missing id")
		elif seen.has(id):
			problems.append("duplicate id")
		seen[id] = true
		var info: String = _check_asset(entry, problems)
		if problems.is_empty():
			print("OK    %s  %s" % [id, info])
		else:
			failures += 1
			print("FAIL  %s  %s" % [id, "; ".join(PackedStringArray(problems))])

	if failures == 0:
		print("PASS (%d assets, 0 failures)" % assets.size())
		return 0
	print("FAIL %d" % failures)
	return 1


## Checks one entry and its .glb. Appends problems to `problems`. Returns a short info string.
func _check_asset(entry: Dictionary, problems: Array[String]) -> String:
	var id: String = String(entry.get("id", ""))
	var family: String = String(entry.get("family", ""))
	var file: String = String(entry.get("file", ""))
	var global_file: String = AssetKit.to_global(file)
	if file.is_empty() or not FileAccess.file_exists(global_file):
		problems.append("glb missing (%s)" % file)
		return ""
	var scene: Node3D = AssetKit.load_glb_scene(file)
	if scene == null:
		problems.append("glb does not load via GLTFDocument")
		return ""

	var meshes: Array = AssetKit.flatten_meshes(scene)
	var tris: int = 0
	var names: Dictionary = {}
	for item in meshes:
		var mi: MeshInstance3D = item["node"]
		names[String(mi.name)] = true
		tris += AssetKit.count_mesh_triangles(mi.mesh)
	if meshes.is_empty() or tris == 0:
		problems.append("no triangles in glb")

	var budget: int = _triangle_budget(entry, id, family)
	if tris > budget:
		problems.append("triangles %d over budget %d" % [tris, budget])
	if int(entry.get("triangles", -1)) != tris:
		problems.append("manifest triangles %s != file %d" % [str(entry.get("triangles", "?")), tris])

	var bounds: AABB = AssetKit.mesh_bounds(scene)
	var pivot: String = String(entry.get("pivot", "base"))
	match pivot:
		"base":
			if absf(bounds.position.y) > PIVOT_TOLERANCE:
				problems.append("pivot: min.y %.3f not at ground" % bounds.position.y)
		"rim":
			if absf(bounds.end.y) > PIVOT_TOLERANCE:
				problems.append("pivot: rim max.y %.3f not at 0" % bounds.end.y)
		"sunk":
			if bounds.position.y > PIVOT_TOLERANCE or bounds.end.y < 0.2:
				problems.append("pivot: sunk model must span the ground plane (min.y %.3f, max.y %.3f)" % [bounds.position.y, bounds.end.y])
		_:
			problems.append("unknown pivot '%s'" % pivot)

	_check_collision(entry, id, family, problems)

	var parts: Array = entry.get("parts", [])
	for part in parts:
		if not names.has(String(part)):
			problems.append("part '%s' not found in glb" % String(part))

	scene.free()
	return "tris %d/%d  size %.2fx%.2fx%.2f  pivot %s  collision %s" % [
		tris, budget, bounds.size.x, bounds.size.y, bounds.size.z, pivot, _collision_kind(entry)]


func _check_collision(entry: Dictionary, id: String, family: String, problems: Array[String]) -> void:
	var collision: Variant = entry.get("collision", null)
	var visual_only: bool = bool(entry.get("visual_only", false))
	if collision == null:
		if not visual_only:
			problems.append("collision missing and not visual_only")
		if family == "trees" or id.begins_with("flagstick"):
			problems.append("collision required for %s" % ("trees" if family == "trees" else "flagstick"))
		return
	if typeof(collision) != TYPE_DICTIONARY:
		problems.append("collision is not an object")
		return
	var c: Dictionary = collision
	var kind: String = String(c.get("kind", ""))
	match kind:
		"tree":
			for key in ["trunk_radius", "trunk_height", "crowns"]:
				if not c.has(key):
					problems.append("tree collision lacks %s" % key)
			var crowns: Variant = c.get("crowns", [])
			if typeof(crowns) != TYPE_ARRAY or (crowns as Array).is_empty() or (crowns as Array).size() > 3:
				problems.append("tree collision needs 1-3 crowns")
		"cylinder":
			if not c.has("radius") or not c.has("height"):
				problems.append("cylinder collision lacks radius/height")
		"sphere":
			if not c.has("center") or not c.has("radius"):
				problems.append("sphere collision lacks center/radius")
		_:
			problems.append("unknown collision kind '%s'" % kind)
	if family == "trees" and kind != "tree":
		problems.append("trees must use collision kind tree")
	if id.begins_with("flagstick") and kind != "cylinder":
		problems.append("flagstick must use collision kind cylinder")


func _collision_kind(entry: Dictionary) -> String:
	var collision: Variant = entry.get("collision", null)
	if typeof(collision) == TYPE_DICTIONARY:
		return String((collision as Dictionary).get("kind", "?"))
	return "none"


## Budget from the spec: trees 1200 (ids with "small" 600), props 400, nature rocks 300 and shrubs 500.
## An entry may set "max_triangles" to override.
func _triangle_budget(entry: Dictionary, id: String, family: String) -> int:
	if entry.has("max_triangles"):
		return int(entry["max_triangles"])
	match family:
		"trees":
			return 600 if id.contains("small") else 1200
		"props":
			return 400
		"nature":
			return 300 if id.begins_with("rock") else 500
	return 1200
