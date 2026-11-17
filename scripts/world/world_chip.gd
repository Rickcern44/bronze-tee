class_name WorldChip
extends Node3D
## A text chip that floats in the world, always faces the camera and keeps a constant on-screen size.

const LABEL_FONT_SIZE := 30
const LABEL_PIXEL_SIZE := 0.01
const SCREEN_TEXT_PX := 15.0
const PAD_X := 16.0
const PAD_Y := 7.0
const RADIUS := 10.0
const BORDER := 2.0

var text := ""
var _background: MeshInstance3D
var _mesh := ArrayMesh.new()
var _label: Label3D

func _init() -> void:
	_background = MeshInstance3D.new()
	_background.mesh = _mesh
	_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := FxMeshBuilder.make_material(true)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.render_priority = 0
	_background.material_override = material
	add_child(_background)
	_label = Label3D.new()
	_label.font = HudFonts.condensed(700, 1.0)
	_label.font_size = LABEL_FONT_SIZE
	_label.pixel_size = LABEL_PIXEL_SIZE
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.shaded = false
	_label.outline_size = 0
	_label.render_priority = 1
	add_child(_label)

func set_chip(new_text: String, fill: Color, text_color: Color, border: Color = Color(0, 0, 0, 0)) -> void:
	text = new_text
	_label.text = new_text
	_label.modulate = text_color
	var font := _label.font
	var text_size := font.get_string_size(new_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	var half := Vector2(text_size.x + PAD_X * 2.0, font.get_height(LABEL_FONT_SIZE) + PAD_Y * 2.0) * 0.5 * LABEL_PIXEL_SIZE
	var builder := FxMeshBuilder.new()
	if border.a > 0.0:
		_rounded(builder, half, RADIUS * LABEL_PIXEL_SIZE, border)
		_rounded(builder, half - Vector2.ONE * BORDER * LABEL_PIXEL_SIZE, (RADIUS - BORDER) * LABEL_PIXEL_SIZE, fill)
	else:
		_rounded(builder, half, RADIUS * LABEL_PIXEL_SIZE, fill)
	builder.commit(_mesh)

static func _rounded(builder: FxMeshBuilder, half: Vector2, radius: float, color: Color) -> void:
	var outline := PackedVector3Array()
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for corner_index in range(4):
		var corner: Vector2 = corners[corner_index]
		var center := Vector2(half.x - radius, half.y - radius) * corner
		var start := corner_index * PI * 0.5
		for step in range(5):
			var angle := start + PI * 0.5 * step / 4.0
			outline.append(Vector3(center.x + cos(angle) * radius, center.y + sin(angle) * radius, 0))
	for i in range(outline.size()):
		builder.triangle(Vector3.ZERO, outline[i], outline[(i + 1) % outline.size()], color, color, color)

func _process(_delta: float) -> void:
	if not visible or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	var per_pixel := FxView.world_per_pixel(camera, global_position)
	scale = Vector3.ONE * (SCREEN_TEXT_PX * per_pixel / (LABEL_FONT_SIZE * LABEL_PIXEL_SIZE))
