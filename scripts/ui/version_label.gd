class_name VersionLabel
extends Label
## Small build-version tag for the HUD corner. Reads application/config/version,
## which tools/version.sh --stamp fills at export time; "dev" when it is unset.

const SETTING := "application/config/version"
const FALLBACK := "dev"

static func version_string() -> String:
	var version := str(ProjectSettings.get_setting(SETTING, "")).strip_edges()
	return FALLBACK if version.is_empty() else version

static func display_text() -> String:
	var version := version_string()
	return version if version == FALLBACK else "v" + version

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = display_text()
	add_theme_font_size_override("font_size", HudTheme.FS_MICRO)
	add_theme_color_override("font_color", Color(HudPalette.MUTED, 0.85))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	add_theme_constant_override("outline_size", 3)
