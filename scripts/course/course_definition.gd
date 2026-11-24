class_name CourseDefinition
extends Resource

@export var display_name: String = "Royal Crest"
@export var id: String = "royal_crest"
@export_enum("real", "fictional") var source_kind: String = "fictional"
@export var provenance: Array[Dictionary] = []
@export var crs: String = ""
@export var origin_latlon: Vector2 = Vector2.ZERO
@export_multiline var notes: String = ""
@export var holes: Array[Resource] = []
