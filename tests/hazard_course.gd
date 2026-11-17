extends "res://scripts/main.gd"
# A test-only sand patch retains bunker-physics coverage without inventing a bunker on Royal Crest hole 1.
func _in_bunker(pos: Vector3) -> bool:
	return _in_ellipse(pos.x, pos.z, 24.0, -185.0, 8.0, 24.0)
