extends SceneTree
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MAP := "res://config/maps/relic_depot.json"
const OUT := "res://art_source/relic_depot_integration/"
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("RELIC_DEPOT FAIL " + message)
func _run() -> void:
	var document: Dictionary = MapDocument.load_path(MAP)
	expect(document.get("map_id") == "relic_depot", "saved map loads")
	var build: Dictionary = MapRuntime.validate_build(document)
	expect(build.ok, "editor/runtime builds every object: " + str(build.errors))
	ProjectSettings.set_setting("socom/session/selected_map_document", document)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	root.size = Vector2i(1280, 800)
	for frame in 45:
		await physics_frame
	expect(game.active_map_document.get("map_id") == "relic_depot", "main.tscn consumes this map")
	expect(game.find_children("*", "WorldEnvironment", true, false).size() == 1, "one authored environment, no fallback environment")
	for label: Label3D in game.find_children("BombSiteLetter", "Label3D", true, false):
		expect(not label.fixed_size, "bomb-site lettering stays in world units")
	var player := game.get_node("Player") as CharacterBody3D
	var driver: Node = player.get_node("Mannequin/ProductionAnimation")
	var skeleton: Skeleton3D = driver.skeleton
	expect(skeleton.get_bone_count() == 65, "65-bone runtime contract preserved")
	expect(not skeleton.has_meta("authored_skin"), "original character retained without replacement skin")
	var pieces := skeleton.find_children("RelicNVG_*", "MeshInstance3D", true, false)
	expect(pieces.is_empty(), "no replacement character pieces or bundled guns")
	var original := skeleton.find_child("armlower", true, false) as MeshInstance3D
	expect(original != null and original.visible, "original player mesh visible")
	expect(driver.weapon_node != null, "canonical equipped weapon remains")
	expect(player.is_on_floor(), "player settles on map floor")
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .38
	capsule.height = 1.85
	for object: Dictionary in document.objects:
		if not str(object.type).ends_with("spawn"):
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = MapDocument.data_to_vector(object.position) + Vector3(0, .98, 0)
		query.exclude = [player.get_rid()]
		query.collision_mask = 1
		expect(space.intersect_shape(query).is_empty(), "spawn clearance " + str(object.name))
	# Continuous east-flank route, capsule-volume checked at one metre intervals.
	for z in range(-24, 25):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = Vector3(18, 1.1, z)
		query.exclude = [player.get_rid()]
		query.collision_mask = 1
		expect(space.intersect_shape(query).is_empty(), "east flank route z=" + str(z))
	if OS.get_cmdline_user_args().has("--render"):
		await _capture("gameplay.png")
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.position = Vector3(57, 60, 62)
		camera.look_at(Vector3(0, 0, 0))
		camera.current = true
		await _capture("overview.png")
		camera.position = player.global_position + Vector3(2.4, 1.4, -3.2)
		camera.look_at(player.global_position + Vector3(0, 1.1, 0))
		await _capture("character_front.png")
		var before: Vector3 = player.global_position
		Input.action_press("move_forward")
		for step in 3:
			for frame in 8:
				await physics_frame
			camera.position = player.global_position + Vector3(2.4, 1.4, -3.2)
			camera.look_at(player.global_position + Vector3(0, 1.1, 0))
			await _capture("walk_%d.png" % step)
		Input.action_release("move_forward")
		expect(player.global_position.distance_to(before) > 0.25, "canonical movement responds during skin render")
		for frame in 12:
			await physics_frame
		Input.action_press("crouch")
		await physics_frame
		await physics_frame
		Input.action_release("crouch")
		for frame in 18:
			await physics_frame
		camera.position = player.global_position + Vector3(2.4, 1.3, -3.2)
		camera.look_at(player.global_position + Vector3(0, .85, 0))
		await _capture("crouch.png")
		camera.queue_free()
	var result := {"pass": failures.is_empty(), "failures": failures, "objects": document.objects.size(), "character_pieces": pieces.size(), "runtime_bones": skeleton.get_bone_count()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT + "regression.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("RELIC_DEPOT_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", result)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
func _capture(filename: String) -> void:
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var pixels := root.get_texture().get_image()
	expect(pixels != null and not pixels.is_empty(), "rendered pixels")
	if pixels != null:
		expect(pixels.save_png(OUT + filename) == OK, "save " + filename)
