extends SceneTree
# Structural checks of the imported Royal Crest course (the project default):
# scorecard, provenance, and per-hole geometry on the baked surface maps.
# tests/royal_crest_round_check.gd plays the round; this checks the data it plays on.

const PARS := [4, 3, 4, 5, 3, 4, 4, 4, 4, 4, 4, 3, 4, 5, 4, 5, 3, 4]
const BLUE := [382, 224, 394, 553, 164, 432, 442, 313, 421, 398, 345, 229, 346, 544, 445, 517, 215, 382]
const WHITE := [353, 207, 345, 544, 153, 417, 344, 300, 396, 338, 321, 204, 318, 532, 433, 479, 172, 349]

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var course = game.COURSE
	assert(course.id == "royal_crest" and course.source_kind == "real" and course.display_name == "Royal Crest")
	assert(course.crs == "EPSG:32617" and course.origin_latlon != Vector2.ZERO)
	var provenance_text := ""
	for item in course.provenance:
		provenance_text += str(item)
	for needle in ["USGS", "Public domain", "OpenStreetMap contributors", "ODbL", "stymie.golf"]:
		assert(provenance_text.contains(needle), "course provenance must credit " + needle)
	assert(FileAccess.file_exists("res://resources/courses/royal_crest/ATTRIBUTION.md"))
	assert(game.HOLES.size() == 18)
	var total_par := 0
	for index in range(18):
		var hole = game.HOLES[index]
		var label := "hole %d" % (index + 1)
		game._load_hole(index)
		total_par += hole.par
		assert(hole.number == index + 1 and hole.par == PARS[index], label + " number/par")
		assert(int(hole.yards) == WHITE[index] and int(hole.blue_tee_yards) == BLUE[index], label + " scorecard yardage")
		assert(hole.black_tee_yards == 0.0 and game._tee_count() == 2, label + " offers white and blue tees only")
		assert(hole.surface_map_file != "" and hole.elevation_file != "" and hole.origin_latlon != Vector2.ZERO, label + " is mapped")
		assert(game.surface_map != null, label + " surface map loaded")
		# The crop origin is shared by the heightmap and surface map and reaches the whole hole.
		assert(hole.surface_map_origin == hole.elevation_origin, label + " crop origin")
		var crop_min_x: float = hole.surface_map_origin.x
		var crop_max_x: float = crop_min_x + (hole.surface_map_dimensions.x - 1) * hole.surface_map_spacing
		var crop_max_z: float = hole.surface_map_origin.y
		var crop_min_z: float = crop_max_z - (hole.surface_map_dimensions.y - 1) * hole.surface_map_spacing
		for point in hole.fairway_centerline:
			assert(point.x > crop_min_x + 20.0 and point.x < crop_max_x - 20.0 and point.y > crop_min_z + 20.0 and point.y < crop_max_z - 20.0, label + " centerline inside crop")
		for tee_offset in [Vector2.ZERO, hole.blue_tee_offset]:
			var tee: Vector2 = hole.tee_position + tee_offset
			assert(tee.x > crop_min_x and tee.x < crop_max_x and tee.y > crop_min_z and tee.y < crop_max_z, label + " tee pads inside crop")
		# Tee, cup and green line up with the baked map.
		assert(game._mapped_surface(hole.tee_position.x, hole.tee_position.y) == game.Surface.TEE, label + " white tee on a tee surface")
		assert(game._mapped_surface(hole.cup_position.x, hole.cup_position.y) == game.Surface.GREEN, label + " cup on the green")
		assert(game._on_green(game.CUP), label + " game agrees the cup is on the green")
		var green_cells := 0
		var max_slope := 0.0
		var max_rim_slope := 0.0
		for x in range(-30, 31):
			for z in range(-30, 31):
				var pos: Vector3 = game.CUP + Vector3(float(x), 0, float(z))
				if game._on_green(pos):
					green_cells += 1
					var slope: float = game._ground_slope(pos).length()
					# Interior = every sample within 2.5 m is green. The plane fit caps interior
					# slope at 2%; the last metres blend into the surrounding lidar terrain.
					var interior := true
					for dx in [-2.5, 0.0, 2.5]:
						for dz in [-2.5, 0.0, 2.5]:
							interior = interior and game._on_green(pos + Vector3(dx, 0, dz))
					if interior:
						max_slope = maxf(max_slope, slope)
					else:
						max_rim_slope = maxf(max_rim_slope, slope)
		assert(green_cells > 250, label + " green is a real green (%d m2)" % green_cells)
		assert(max_slope < .021, label + " fitted green slope %.3f" % max_slope)
		assert(max_rim_slope < .11, label + " green rim slope %.3f" % max_rim_slope)
		var carry := Vector2(hole.cup_position.x - hole.tee_position.x, hole.cup_position.y - hole.tee_position.y).length()
		assert(carry > 100.0 and carry < hole.yards * 0.9144 * 1.1, label + " tee-to-cup distance %.0f m vs %d yd" % [carry, hole.yards])
		for stimp in game.GREEN_SPEEDS:
			game.physics_bridge.SetGreenSpeed(stimp)
			for offset in [Vector3(-5, 0, 4), Vector3(5, 0, -4), Vector3(0, 0, 5)]:
				for heading in [90.0, 180.0, 270.0]:
					game.ball_position = game.CUP + offset
					game.ball_position.y = game._ground_height(game.ball_position.x, game.ball_position.z) + game.BALL_RADIUS
					game.club_index = game.CLUBS.size() - 1
					game.aim = heading
					var result: Dictionary = game.physics_bridge.Forecast(game._shot_data(.3), false, false)
					assert(result.phase == 2 or result.phase == 3, label + " putt did not stop at stimp %.0f" % stimp)
					assert(game._on_green(result.position), label + " short putt left the green")
		print("PASS %s: par %d, %d yd, green %d m2, interior slope %.2f%%, rim %.2f%%" % [label, hole.par, hole.yards, green_cells, max_slope * 100.0, max_rim_slope * 100.0])
	assert(total_par == 71)
	# White and blue tees: T cycles between them and a remembered black index clamps to blue.
	for index in [0, 6, 11]:
		var hole = game.HOLES[index]
		game.tee_index = 0
		game._load_hole(index)
		var white_tee: Vector3 = game.TEE
		assert(game._selected_tee_name() == "WHITE" and game._selected_tee_yards() == hole.yards)
		game.tee_index = 1
		game._load_hole(index)
		assert(game._selected_tee_name() == "BLUE" and game._selected_tee_yards() == hole.blue_tee_yards)
		var back := Vector2(game.TEE.x - white_tee.x, game.TEE.z - white_tee.z).length()
		assert(absf(back - (hole.blue_tee_yards - hole.yards) * 0.9144) < 1.0, "blue tee sits the scorecard difference behind white (%.1f m)" % back)
		assert(game.TEE.z > white_tee.z, "blue tee is behind the white tee")
		game.tee_index = 2
		game._load_hole(index)
		assert(game._selected_tee_name() == "BLUE" and game._tee_count() == 2, "tee index clamps to the tees the hole offers")
	game.tee_index = 0
	print("PASS Royal Crest course data: 18 holes, par 71, provenance and attribution")
	quit()
