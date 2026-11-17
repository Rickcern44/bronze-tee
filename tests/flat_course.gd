extends "res://scripts/main.gd"

# Neutral calibration surface: level fairway, no hazards, trees, or cup.
func _ground_height(_x: float, _z: float) -> float: return 0.0
func _on_green(_pos: Vector3) -> bool: return false
func _in_water(_pos: Vector3) -> bool: return false
func _in_bunker(_pos: Vector3) -> bool: return false
func _tree_hit(_from: Vector3, _to: Vector3) -> bool: return false
func _fairway_contains(_x: float, _z: float) -> bool: return true
func _try_sink(_previous: Vector3) -> bool: return false
