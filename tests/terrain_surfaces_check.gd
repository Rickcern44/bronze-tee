extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var previous_cup_z := INF
	for hole in range(game.HOLES.size()):
		game._load_hole(hole)
		await process_frame
		var S = game.Surface
		var cup: Vector3 = game.CUP
		# Shader parameters follow the hole.
		var material: ShaderMaterial = game.terrain_material
		if material == null or material.shader == null:
			return fail("hole %d: terrain material or shader missing" % hole)
		var cup_param: Vector2 = material.get_shader_parameter("cup")
		if not is_equal_approx(cup_param.y, cup.z) or is_equal_approx(cup.z, previous_cup_z):
			return fail("hole %d: shader cup did not update on _load_hole" % hole)
		previous_cup_z = cup.z
		var water: Array = game._water_features()
		if int(material.get_shader_parameter("water_count")) != water.size():
			return fail("hole %d: water_count not updated" % hole)
		var ellipses: PackedVector4Array = material.get_shader_parameter("water_ellipses")
		for i in range(water.size()):
			if not is_equal_approx(ellipses[i].x, water[i][0]) or not is_equal_approx(ellipses[i].w, water[i][3]):
				return fail("hole %d: water ellipse %d not updated" % [hole, i])
		for uniform_name in game.TERRAIN_TEXTURES:
			if material.get_shader_parameter(uniform_name) == null:
				return fail("missing texture uniform " + uniform_name)
		# Fairway, first cut, rough agree with _lie.
		var z := -100.0
		var center: float = game._fairway_center(z)
		var width: float = game._fairway_width(z)
		var cases := [
			[Vector3(center + width - 1.0, 0, z), S.FAIRWAY, "Fairway"],
			[Vector3(center + width + 1.5, 0, z), S.FIRST_CUT, "FirstCut"],
			[Vector3(center + width + 3.0 + 3.0, 0, z), S.SECOND_CUT, "Rough"],
			[Vector3(center - width - 3.0 - 6.0 - 3.0, 0, z), S.DEEP_ROUGH, "Rough"],
			[Vector3(cup.x + 3.0, 0, cup.z), S.GREEN, "Green"],
		]
		for item in cases:
			var pos: Vector3 = item[0]
			if water.size() > 0 and game._in_water(pos) or game._on_path(pos.x, pos.z):
				continue # hazards take priority over the base surface
			if game._surface_at(pos.x, pos.z) != item[1]:
				return fail("hole %d: surface at %s was %d, expected %d" % [hole, pos, game._surface_at(pos.x, pos.z), item[1]])
			if game._lie(pos) != item[2]:
				return fail("hole %d: lie at %s was %s, expected %s" % [hole, pos, game._lie(pos), item[2]])
		# Collar ring and tee ellipse.
		var collar_x: float = cup.x + game.GREEN_RADII.x * 1.07
		if game._surface_at(collar_x, cup.z) != S.COLLAR:
			return fail("hole %d: collar not classified" % hole)
		if game._surface_at(game.TEE.x, game.TEE.z) != S.TEE:
			return fail("hole %d: tee not classified" % hole)
		# Path: a point centred on the path alongside the fairway.
		var path_z := -60.0
		var path_x: float = game.PATH_CENTER_X + game.PATH_SWAY * sin(path_z * game.PATH_SWAY_FREQUENCY) + game._fairway_dogleg_shift(path_z)
		if game._surface_at(path_x, path_z) != S.PATH:
			return fail("hole %d: path not classified" % hole)
		# Every water ellipse centre is water and is never a land lie.
		for feature in water:
			if game._surface_at(feature[0], feature[1]) != S.WATER:
				return fail("hole %d: water not classified" % hole)
		# Exhaustive grid: second cut and deep rough both give "Rough".
		for x in range(-60, 61, 4):
			for zz in range(-int(absf(cup.z)) - 10, 10, 6):
				var surface: int = game._surface_at(float(x), float(zz))
				var lie: String = game._lie(Vector3(x, 0, zz))
				if surface == S.SECOND_CUT or surface == S.DEEP_ROUGH:
					if lie != "Rough":
						return fail("hole %d: (%d, %d) second/deep rough gave lie %s" % [hole, x, zz, lie])
				elif surface == S.FAIRWAY and lie != "Fairway":
					return fail("hole %d: (%d, %d) fairway gave lie %s" % [hole, x, zz, lie])
				elif surface == S.FIRST_CUT and lie != "FirstCut":
					return fail("hole %d: (%d, %d) first cut gave lie %s" % [hole, x, zz, lie])
				elif surface == S.GREEN and lie != "Green":
					return fail("hole %d: (%d, %d) green gave lie %s" % [hole, x, zz, lie])
	print("PASS terrain surface classification and shader parameters on all holes")
	quit()
