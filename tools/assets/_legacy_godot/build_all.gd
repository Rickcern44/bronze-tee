## Regenerates every asset from scratch (headless):
##   1. writes the two palette PNGs,
##   2. deletes old .glb files under assets/models,
##   3. runs build(out_dir) on every tools/assets/families/*.gd (not starting with "_"),
##      out_dir = res://assets/models/<family file name>,
##   4. writes assets/models/manifest.json (entries sorted by id).
## Exit code 0 on success, 1 on any error.
## Run: perl -e 'alarm 300; exec @ARGV' /Users/rickcerny/Downloads/Godot_mono.app/Contents/MacOS/Godot --headless --path /Users/rickcerny/dev/sandbox/bronze-tee --script res://tools/assets/build_all.gd
extends SceneTree

const FAMILIES_DIR: String = "res://tools/assets/families"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: int = 0
	var err: Error = AssetKit.write_palette_pngs()
	if err != OK:
		push_error("build_all: cannot write palettes: %s" % error_string(err))
		return 1
	print("palettes written: %s, %s" % [AssetKit.PALETTE_DEFAULT, AssetKit.PALETTE_AUTUMN])

	# With `-- --family=<name>` only that family is cleared, built and written to its partial manifest.
	var only: String = AssetKit.family_filter()
	if only.is_empty():
		_remove_glbs(AssetKit.to_global(AssetKit.MODELS_DIR))
	else:
		_remove_glbs(AssetKit.to_global("%s/%s" % [AssetKit.MODELS_DIR, only]))

	var entries: Array = []
	var seen_ids: Dictionary = {}
	var families: Array[String] = _family_scripts()
	if not only.is_empty():
		families = families.filter(func(p: String) -> bool: return p.get_file().get_basename() == only)
		if families.is_empty():
			push_error("build_all: no family script named %s" % only)
			return 1
	for script_path in families:
		var family: String = script_path.get_file().get_basename()
		var script: GDScript = load(script_path) as GDScript
		if script == null:
			push_error("build_all: cannot load family script %s" % script_path)
			errors += 1
			continue
		var inst: Object = script.new()
		if not inst.has_method("build"):
			push_error("build_all: %s has no build(out_dir) method" % script_path)
			errors += 1
			continue
		var out_dir: String = "%s/%s" % [AssetKit.MODELS_DIR, family]
		var result: Variant = inst.call("build", out_dir)
		if typeof(result) != TYPE_ARRAY:
			push_error("build_all: build() of %s did not return an Array" % family)
			errors += 1
			continue
		var count: int = 0
		for e in result:
			if typeof(e) != TYPE_DICTIONARY or (e as Dictionary).is_empty():
				push_error("build_all: family %s returned an empty or invalid entry" % family)
				errors += 1
				continue
			var id: String = String((e as Dictionary).get("id", ""))
			if seen_ids.has(id):
				push_error("build_all: duplicate asset id %s" % id)
				errors += 1
				continue
			seen_ids[id] = true
			entries.append(e)
			count += 1
		print("family %s: %d assets" % [family, count])

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))

	var manifest: Dictionary = {
		"version": 1,
		"palettes": {"default": AssetKit.PALETTE_DEFAULT, "autumn": AssetKit.PALETTE_AUTUMN},
		"assets": entries,
	}
	var manifest_path: String = AssetKit.to_global(AssetKit.manifest_path())
	err = AssetKit.ensure_dir(manifest_path.get_base_dir())
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if err != OK or file == null:
		push_error("build_all: cannot write %s" % manifest_path)
		return 1
	file.store_string(JSON.stringify(AssetKit.to_json_safe(manifest), "\t") + "\n")
	file.close()

	print("manifest: %d assets -> %s" % [entries.size(), manifest_path])
	if errors > 0:
		print("build_all: FAILED with %d error(s)" % errors)
		return 1
	print("build_all: OK")
	return 0


## Sorted res:// paths of family scripts (*.gd, skipping names that start with "_").
func _family_scripts() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(FAMILIES_DIR)
	if dir == null:
		push_error("build_all: cannot open %s" % FAMILIES_DIR)
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension() == "gd" and not name.begins_with("_"):
			out.append(FAMILIES_DIR.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Deletes every .glb (and its .glb.import) below an absolute folder, recursively.
func _remove_glbs(global_dir: String) -> void:
	var dir: DirAccess = DirAccess.open(global_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name != "." and name != "..":
			if dir.current_is_dir():
				_remove_glbs(global_dir.path_join(name))
			elif name.get_extension() == "glb" or name.ends_with(".glb.import"):
				dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
