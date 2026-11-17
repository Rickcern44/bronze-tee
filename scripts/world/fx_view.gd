class_name FxView
extends RefCounted
## Camera helpers for effects that keep a constant on-screen size.

## World units covered by one canvas pixel at the depth of `point`.
static func world_per_pixel(camera: Camera3D, point: Vector3) -> float:
	if camera == null:
		return 0.01
	var depth := maxf(-(camera.global_transform.affine_inverse() * point).z, 0.1)
	var viewport_height := camera.get_viewport().get_visible_rect().size.y
	return depth * 2.0 * tan(deg_to_rad(camera.fov * 0.5)) / viewport_height
