class_name HudFonts
extends RefCounted
## Every font the HUD and world labels use is created here. Swap files or families in this one place.

const CONDENSED_FILES := {
	500: "res://assets/fonts/BarlowCondensed-Medium.ttf",
	600: "res://assets/fonts/BarlowCondensed-SemiBold.ttf",
	700: "res://assets/fonts/BarlowCondensed-Bold.ttf",
}
const BODY_FILES := {
	500: "res://assets/fonts/Barlow-Medium.ttf",
	600: "res://assets/fonts/Barlow-SemiBold.ttf",
}
const CONDENSED_FALLBACK_NAMES: PackedStringArray = ["Barlow Condensed", "Arial Narrow", "Helvetica Neue"]
const BODY_FALLBACK_NAMES: PackedStringArray = ["Barlow", "Helvetica Neue", "Arial"]

static var _cache: Dictionary = {}

static func _system(names: PackedStringArray, weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = names
	font.font_weight = weight
	return font

static func _load(path: String, names: PackedStringArray, weight: int) -> Font:
	var system := _system(names, weight)
	if not ResourceLoader.exists(path):
		return system
	var file := load(path) as FontFile
	if file == null:
		return system
	file.fallbacks = [system]
	return file

static func _tracked(base: Font, tracking_px: float) -> Font:
	if is_zero_approx(tracking_px):
		return base
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = int(round(tracking_px))
	return variation

## Barlow Condensed at weight 500, 600 or 700, with optional letter spacing in pixels.
static func condensed(weight: int = 600, tracking_px: float = 0.0) -> Font:
	var key := "c%d_%.1f" % [weight, tracking_px]
	if not _cache.has(key):
		_cache[key] = _tracked(_load(CONDENSED_FILES.get(weight, CONDENSED_FILES[600]), CONDENSED_FALLBACK_NAMES, weight), tracking_px)
	return _cache[key]

## Barlow at weight 500 or 600.
static func body(weight: int = 500) -> Font:
	var key := "b%d" % weight
	if not _cache.has(key):
		_cache[key] = _load(BODY_FILES.get(weight, BODY_FILES[500]), BODY_FALLBACK_NAMES, weight)
	return _cache[key]
