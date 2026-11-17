extends RefCounted

# A reusable, low-poly tuft of closely cut fairway grass. Dimensions are in meters.
# Palette matches the terrain fairway textures; main.gd tints it per surface.
# Each blade has a darker root, a lighter tip and a slightly different lean.
static func create_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_color := Color("5AAD38")
	var middle_color := Color("6FC043")
	var tip_color := Color("86D25A")
	for blade in range(6):
		var angle := float(blade) * TAU / 6.0
		var right := Vector3(cos(angle), 0, sin(angle))
		var offset := Vector3(cos(angle * 2.0), 0, sin(angle * 2.0)) * (0.035 + float(blade % 2) * 0.018)
		var width := 0.018 + float(blade % 3) * 0.004
		var height := 0.105 + float((blade * 3) % 5) * 0.015
		var lean := Vector3(sin(angle + 0.4), 0, cos(angle + 0.4)) * 0.04
		var bottom_left := offset - right * width
		var bottom_right := offset + right * width
		var middle := offset + lean * 0.55 + Vector3.UP * height * 0.62
		var middle_left := middle - right * width * 0.55
		var middle_right := middle + right * width * 0.55
		var tip := offset + lean + Vector3.UP * height
		for vertex in [
			[bottom_left, root_color], [bottom_right, root_color], [middle_right, middle_color],
			[bottom_left, root_color], [middle_right, middle_color], [middle_left, middle_color],
			[middle_left, middle_color], [middle_right, middle_color], [tip, tip_color],
		]:
			surface.set_color(vertex[1])
			surface.add_vertex(vertex[0])
	surface.generate_normals()
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	return mesh
