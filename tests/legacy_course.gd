extends RefCounted
## Pins a test to the four-hole legacy fixture course instead of the project default.
## Usage: var game = load("res://tests/legacy_course.gd").game()

const COURSE := "res://resources/courses/royal_crest_legacy/course.tres"

static func game() -> Node:
	var instance: Node = load("res://scenes/main.tscn").instantiate()
	instance.course_path_override = COURSE
	return instance
