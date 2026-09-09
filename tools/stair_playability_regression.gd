extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")
const PlayerScene := preload("res://scenes/player/operator_player.tscn")
const ImportedBuilder := preload("res://scripts/maps/socom_imported_map_asset_builder.gd")
const AssetLibrary := preload("res://scripts/maps/socom_map_asset_library.gd")

const STAIR_SIZE := Vector3(2.4, 1.8, 3.2)
const LOWER_STOP_Z := 4.0
const UPPER_STOP_Z := -4.0
const MAX_TRAVEL_FRAMES := 180

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	world.name = "StairPlayabilityRegressionWorld"
	root.add_child(world)
	_add_box(
		world,
		"LowerLanding",
		Vector3(8.0, 0.30, 8.0),
		Vector3(0.0, -0.15, STAIR_SIZE.z * 0.5 + 4.0)
	)
	_add_box(
		world,
		"UpperLanding",
		Vector3(8.0, 0.30, 8.0),
		Vector3(0.0, STAIR_SIZE.y - 0.15, -STAIR_SIZE.z * 0.5 - 4.0)
	)

	var stair_object := MapDocument.make_object(
		&"stairs",
		Vector3(0.0, STAIR_SIZE.y * 0.5, 0.0),
		STAIR_SIZE
	)
	stair_object["id"] = "stair_playability_fixture"
	stair_object["name"] = "Playable Authored Stairs"
	var stair_properties: Dictionary = stair_object.get("properties", {})
	stair_properties["steps"] = 10
	stair_object["properties"] = stair_properties
	var imported := "--imported" in OS.get_cmdline_user_args()
	if imported:
		var path := "res://assets/environment/tactical_courtyard_kit/concrete_stairs_6step.glb"
		var loaded := AssetLibrary.instantiate_asset(path)
		var visual := loaded.get("scene") as Node3D
		if visual == null:
			_expect(false, "imported stair asset loads")
			_finish()
			return
		var bounds := ImportedBuilder._combined_mesh_bounds(visual)
		visual.free()
		var scale_value := STAIR_SIZE / bounds.size
		stair_object = MapDocument.make_object(&"imported_asset", Vector3(0, STAIR_SIZE.y * 0.5, 0) - bounds.get_center() * scale_value, scale_value)
		stair_object.properties = {"asset_path": path, "collision_mode": "stair_ramp", "collision_enabled": true}
		# Exercise the saved JSON contract, not a preview-only node modification.
		stair_object = JSON.parse_string(JSON.stringify(stair_object))
	var stairs := MapRuntime.build_object(stair_object, false)
	_expect(stairs != null, "authored stairs build through SocomMapRuntime")
	if stairs == null:
		_finish()
		return
	world.add_child(stairs)
	if "--raw-steps" in OS.get_cmdline_user_args():
		stairs.get_node("TraversalRamp/CollisionShape3D").disabled = true
		for index in 10:
			var height := float(index + 1) * 0.18
			_add_box(world, "RawRiser" + str(index), Vector3(STAIR_SIZE.x, height, 0.32), Vector3(0, height * 0.5, STAIR_SIZE.z * 0.5 - (index + 0.5) * 0.32))
	_expect(
		stairs is StaticBody3D if imported else stairs.get_node_or_null("TraversalRamp") is StaticBody3D,
		"stairs expose one named authoritative traversal ramp"
	)
	var traversal_collision := stairs.get_node_or_null(
		"StairTraversalCollision" if imported else "TraversalRamp/CollisionShape3D"
	) as CollisionShape3D
	_expect(
		traversal_collision != null
		and traversal_collision.shape is ConvexPolygonShape3D
		and (not traversal_collision.disabled or "--raw-steps" in OS.get_cmdline_user_args()),
		"stair traversal ramp has one enabled convex collision surface"
	)
	var visual_step_count := 0
	var enabled_collision_count := 0
	for descendant: Node in stairs.find_children("*", "", true, false):
		if descendant is MeshInstance3D and descendant.name.begins_with("Step"):
			visual_step_count += 1
		if descendant is CollisionShape3D and not (descendant as CollisionShape3D).disabled:
			enabled_collision_count += 1
	_expect(not stairs.find_children("*", "MeshInstance3D", true, false).is_empty() if imported else visual_step_count == 10, "stair visuals remain present")
	_expect(enabled_collision_count == (0 if "--raw-steps" in OS.get_cmdline_user_args() else 1), "fixture uses intended ramp or raw-riser collision")

	var player := PlayerScene.instantiate() as CharacterBody3D
	_expect(player != null, "the real SocomTestPlayer scene instantiates")
	if player == null:
		_finish()
		return
	player.name = "StairTraversalPlayer"
	player.position = Vector3(0.0, 0.05, LOWER_STOP_Z + 0.8)
	player.set_local_input_enabled(false)
	player.set("automatic_vault_enabled", true)
	world.add_child(player)
	if "--capture" in OS.get_cmdline_user_args():
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -30, 0)
		world.add_child(light)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(9, 8, 9)
		camera.look_at(Vector3(0, 2, 0))
	await _step_physics(12)
	_expect(player.is_on_floor(), "player starts grounded on the lower landing")

	var ascent_grounded_frames := 0
	var ascent_frames := 0
	var ascent_peak := player.global_position.y
	var traversal_frames := 0
	var airborne_frames := 0
	for _frame in range(MAX_TRAVEL_FRAMES):
		_queue_world_direction(player, Vector3.FORWARD)
		await physics_frame
		ascent_frames += 1
		if ascent_frames == 60 and "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/stair-ascent.png")
		if player.traversal.is_active(): traversal_frames += 1
		if player.motion_state == player.MotionState.AIRBORNE: airborne_frames += 1
		ascent_peak = maxf(ascent_peak, player.global_position.y)
		if player._movement_floor_contact():
			ascent_grounded_frames += 1
		if player.global_position.z <= UPPER_STOP_Z and player.global_position.y >= STAIR_SIZE.y - 0.12:
			break
	await _idle_player(player, 4)
	print(
		"STAIR_PLAYABILITY_METRIC ascent_frames=%d grounded=%d peak_y=%.3f end=%s"
		% [ascent_frames, ascent_grounded_frames, ascent_peak, player.global_position]
	)
	_expect(player.global_position.z <= UPPER_STOP_Z, "player crosses the full stair run upward")
	_expect(player.global_position.y >= STAIR_SIZE.y - 0.12, "player reaches the upper landing height")
	_expect(player.is_on_floor(), "player settles grounded on the upper landing")
	_expect(
		ascent_grounded_frames >= maxi(ascent_frames - 3, 1),
		"ascent preserves continuous floor contact"
	)

	var descent_grounded_frames := 0
	var descent_frames := 0
	var descent_low := player.global_position.y
	for _frame in range(MAX_TRAVEL_FRAMES):
		_queue_world_direction(player, Vector3.BACK)
		await physics_frame
		descent_frames += 1
		if player.traversal.is_active(): traversal_frames += 1
		if player.motion_state == player.MotionState.AIRBORNE: airborne_frames += 1
		descent_low = minf(descent_low, player.global_position.y)
		if player._movement_floor_contact():
			descent_grounded_frames += 1
		if player.global_position.z >= LOWER_STOP_Z and player.global_position.y <= 0.12:
			break
	await _idle_player(player, 4)
	print(
		"STAIR_PLAYABILITY_METRIC descent_frames=%d grounded=%d low_y=%.3f end=%s"
		% [descent_frames, descent_grounded_frames, descent_low, player.global_position]
	)
	_expect(player.global_position.z >= LOWER_STOP_Z, "player crosses the full stair run downward")
	_expect(player.global_position.y <= 0.12, "player returns to the lower landing height")
	_expect(player.is_on_floor(), "player settles grounded on the lower landing")
	_expect(
		descent_grounded_frames >= maxi(descent_frames - 3, 1),
		"descent preserves continuous floor contact"
	)
	_expect(traversal_frames == 0, "stairs never activate vault, hang or climb; no Jump input required")
	_expect(airborne_frames == 0, "stair edges never trigger airborne animation state")
	_finish()


func _queue_world_direction(player: CharacterBody3D, direction: Vector3) -> void:
	var command := MovementCommand.new()
	command.simulation_tick = Engine.get_physics_frames()
	command.aim_yaw = 0.0
	command.world_move_override = direction
	player.queue_movement_command(command)


func _idle_player(player: CharacterBody3D, frame_count: int) -> void:
	for _frame in range(frame_count):
		_queue_world_direction(player, Vector3.ZERO)
		await physics_frame


func _add_box(parent: Node3D, box_name: String, size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = position
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func _step_physics(frame_count: int) -> void:
	for _frame in range(frame_count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("STAIR_PLAYABILITY_CHECK PASS ", label)
		return
	failures.append(label)
	push_error("STAIR_PLAYABILITY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("STAIR_PLAYABILITY_REGRESSION PASS")
		quit(0)
		return
	print("STAIR_PLAYABILITY_REGRESSION FAIL ", failures)
	quit(1)
