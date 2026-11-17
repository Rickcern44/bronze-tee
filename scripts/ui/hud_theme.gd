class_name HudTheme
extends RefCounted
## The shared HUD Theme: fonts, font sizes, colours and StyleBoxFlats live here.

# Label variations.
const CAPS := &"HudCaps"
const CAPS_MUTED := &"HudCapsMuted"
const NUM := &"HudNum"
const NUM_BOLD := &"HudNumBold"
const NUM_MUTED := &"HudNumMuted"
const HELPER := &"HudHelper"
const BODY := &"HudBody"
# PanelContainer variations.
const PANEL := &"HudPanel"
const PANEL_LIVE := &"HudPanelLive"
const PANEL_ALERT := &"HudPanelAlert"
const PANEL_BANNER := &"HudPanelBanner"
const PANEL_COMPACT := &"HudPanelCompact"
const PANEL_COMPACT_LIVE := &"HudPanelCompactLive"
const WELL := &"HudWell"
const STRIP := &"HudStrip"
const KEY := &"HudKeyCap"
const CHIP := &"HudChip"
const CHIP_ON := &"HudChipOn"
const CHIP_BRONZE := &"HudChipBronze"
const CHIP_OUTLINE := &"HudChipOutline"
const CHIP_LIVE := &"HudChipLive"
const CHIP_CHALK := &"HudChipChalk"
const BADGE := &"HudBadge"

# Font sizes used across components.
const FS_HERO := 60
const FS_NAME := 36
const FS_BIG := 30
const FS_STAT := 26
const FS_TITLE := 22
const FS_TILE := 20
const FS_VALUE := 16
const FS_SMALL := 14
const FS_CAPTION := 12
const FS_MICRO := 11
const FS_HELPER := 13

static var _theme: Theme

static func build() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = HudFonts.body(500)
	theme.default_font_size = FS_HELPER
	_label_variation(theme, CAPS, HudFonts.condensed(600, 1.8), 13, HudPalette.BRONZE_LABEL)
	_label_variation(theme, CAPS_MUTED, HudFonts.condensed(600, 1.2), FS_CAPTION, HudPalette.MUTED)
	_label_variation(theme, NUM, HudFonts.condensed(600), FS_VALUE, HudPalette.CHALK)
	_label_variation(theme, NUM_BOLD, HudFonts.condensed(700), FS_VALUE, HudPalette.CHALK)
	_label_variation(theme, NUM_MUTED, HudFonts.condensed(600), FS_VALUE, HudPalette.MUTED)
	_label_variation(theme, HELPER, HudFonts.body(500), FS_HELPER, HudPalette.MUTED)
	_label_variation(theme, BODY, HudFonts.body(500), FS_HELPER, HudPalette.CHALK)
	_panel(theme, PANEL, _panel_style(HudPalette.PANEL, HudPalette.BRONZE_BORDER, 1, 10, Vector4(14, 12, 14, 12), true))
	_panel(theme, PANEL_LIVE, _panel_style(HudPalette.PANEL, HudPalette.LIVE, 1, 10, Vector4(14, 12, 14, 12), true))
	_panel(theme, PANEL_ALERT, _panel_style(HudPalette.PANEL, HudPalette.FLAG, 1, 10, Vector4(14, 12, 14, 12), true))
	_panel(theme, PANEL_BANNER, _panel_style(HudPalette.PANEL, HudPalette.LIVE, 2, 10, Vector4(20, 12, 20, 12), true))
	_panel(theme, PANEL_COMPACT, _panel_style(HudPalette.PANEL, HudPalette.BRONZE_BORDER, 1, 10, Vector4(18, 8, 18, 8), true))
	_panel(theme, PANEL_COMPACT_LIVE, _panel_style(HudPalette.PANEL, HudPalette.LIVE, 1, 10, Vector4(18, 8, 18, 8), true))
	_panel(theme, WELL, _panel_style(HudPalette.WELL, Color(0, 0, 0, 0), 0, 5, Vector4(8, 6, 8, 6), false))
	_panel(theme, STRIP, _panel_style(HudPalette.STRIP, Color(0, 0, 0, 0), 0, 8, Vector4(10, 6, 10, 6), false))
	var key := _panel_style(HudPalette.WELL, HudPalette.KEY_EDGE, 1, 5, Vector4(5, 0, 5, 0), false)
	key.border_width_bottom = 3
	_panel(theme, KEY, key)
	_panel(theme, CHIP, _panel_style(HudPalette.WELL, Color(0, 0, 0, 0), 0, 5, Vector4(9, 6, 9, 6), false))
	_panel(theme, CHIP_ON, _panel_style(HudPalette.LIVE, Color(0, 0, 0, 0), 0, 5, Vector4(9, 6, 9, 6), false))
	_panel(theme, CHIP_BRONZE, _panel_style(HudPalette.BRONZE, Color(0, 0, 0, 0), 0, 5, Vector4(8, 4, 8, 4), false))
	_panel(theme, CHIP_OUTLINE, _panel_style(Color(0, 0, 0, 0), HudPalette.KEY_EDGE, 1, 4, Vector4(7, 3, 7, 3), false))
	_panel(theme, CHIP_LIVE, _panel_style(HudPalette.LIVE, Color(0, 0, 0, 0), 0, 4, Vector4(7, 4, 7, 4), false))
	_panel(theme, CHIP_CHALK, _panel_style(HudPalette.CHALK, Color(0, 0, 0, 0), 0, 4, Vector4(7, 4, 7, 4), false))
	_panel(theme, BADGE, _panel_style(HudPalette.BRONZE, Color(0, 0, 0, 0), 0, 8, Vector4(0, 0, 0, 0), false))
	_theme = theme
	return theme

static func _label_variation(theme: Theme, name: StringName, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)

static func _panel(theme: Theme, name: StringName, style: StyleBoxFlat) -> void:
	theme.set_type_variation(name, &"PanelContainer")
	theme.set_stylebox("panel", name, style)

## margins: left, top, right, bottom.
static func _panel_style(fill: Color, border: Color, border_width: int, radius: int, margins: Vector4, shadow: bool) -> StyleBoxFlat:
	var style := HudDraw.box(fill, radius, border, border_width)
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	if shadow:
		style.shadow_color = HudPalette.SHADOW
		style.shadow_size = 1
		style.shadow_offset = Vector2(0, 5)
	return style

# ---- Construction helpers shared by components ----

static func label(text: String, variation: StringName = NUM, size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var item := Label.new()
	item.text = text
	item.theme_type_variation = variation
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size > 0:
		item.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		item.add_theme_color_override("font_color", color)
	return item

static func tint(item: Label, color: Color) -> void:
	item.add_theme_color_override("font_color", color)

static func untint(item: Label) -> void:
	item.remove_theme_color_override("font_color")

static func vbox(gap: int = 0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", gap)
	return box

static func hbox(gap: int = 0) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", gap)
	return box

static func panel(variation: StringName = PANEL) -> PanelContainer:
	var item := PanelContainer.new()
	item.theme_type_variation = variation
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

static func spacer() -> Control:
	var item := Control.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item

static func divider() -> Control:
	var item := ColorRect.new()
	item.color = HudPalette.LINE
	item.custom_minimum_size = Vector2(0, 1)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item
