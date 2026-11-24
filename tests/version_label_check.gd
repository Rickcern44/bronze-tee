extends SceneTree

const SETTING := "application/config/version"

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var script: Script = load("res://scripts/ui/version_label.gd")
	assert(script != null, "version_label.gd must load")
	var committed := str(ProjectSettings.get_setting(SETTING, ""))
	# The committed placeholder (or a stamped export) is shown as-is with a "v".
	assert(not VersionLabel.version_string().is_empty())
	if not committed.is_empty():
		assert(VersionLabel.version_string() == committed)
		assert(VersionLabel.display_text() == "v" + committed)
	# Unset or blank setting falls back to "dev".
	ProjectSettings.set_setting(SETTING, "")
	assert(VersionLabel.version_string() == "dev" and VersionLabel.display_text() == "dev")
	ProjectSettings.set_setting(SETTING, "0.1.1-alpha.3+abc1234")
	var label := VersionLabel.new()
	assert(label.text == "v0.1.1-alpha.3+abc1234")
	assert(label.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	label.free()
	ProjectSettings.set_setting(SETTING, committed)
	# The HUD shows it.
	var hud := Hud.new()
	root.add_child(hud)
	await process_frame
	assert(hud.version_label != null and hud.version_label.is_inside_tree())
	assert(not hud.version_label.text.is_empty())
	print("PASS version label: '%s'" % hud.version_label.text)
	hud.queue_free()
	quit()
