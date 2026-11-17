class_name HudDraw
extends RefCounted
## Small drawing helpers for custom-drawn HUD controls.

static func text_centered(canvas: CanvasItem, text: String, font: Font, size: int, rect: Rect2, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := rect.position.y + (rect.size.y + font.get_ascent(size) - font.get_descent(size)) * 0.5
	canvas.draw_string(font, Vector2(rect.position.x + (rect.size.x - width) * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func box(color: Color, radius: int = 0, border_color: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.anti_aliasing = true
	return style

## Dashed rectangle outline.
static func dashed_rect(canvas: CanvasItem, rect: Rect2, color: Color, dash: float = 5.0, gap: float = 4.0, width: float = 1.0) -> void:
	var corners := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y), rect.position]
	for i in range(4):
		var from: Vector2 = corners[i]
		var to: Vector2 = corners[i + 1]
		var length := from.distance_to(to)
		var direction := (to - from) / length
		var at := 0.0
		while at < length:
			canvas.draw_line(from + direction * at, from + direction * minf(at + dash, length), color, width)
			at += dash + gap
