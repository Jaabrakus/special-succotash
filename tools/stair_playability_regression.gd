extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")
const PlayerScene := preload("res://scenes/player/operator_player.tscn")

const STAIR_SIZE := Vector3(2.4, 4.4, 5.8)
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
	var stairs := MapRuntime.build_object(stair_object, false)
	_expect(stairs != null, "authored stairs build through SocomMapRuntime")
	if stairs == null:
		_finish()
		return
	world.add_child(stairs)
	_expect(
		stairs.get_node_or_null("TraversalRamp") is StaticBody3D,
		"stairs expose one named authoritative traversal ramp"
	)
	var traversal_collision := stairs.get_node_or_null(
		"TraversalRamp/CollisionShape3D"
	) as CollisionShape3D
	_expect(
		traversal_collision != null
		and traversal_collision.shape is ConvexPolygonShape3D
		and not traversal_collision.disabled,
		"stair traversal ramp has one enabled convex collision surface"
	)
	var visual_step_count := 0
	var enabled_collision_count := 0
	for descendant: Node in stairs.find_children("*", "", true, false):
		if descendant is MeshInstance3D and descendant.name.begins_with("Step"):
			visual_step_count += 1
		if descendant is CollisionShape3D and not (descendant as CollisionShape3D).disabled:
			enabled_collision_count += 1
	_expect(visual_step_count == 10, "all ten authored stair treads remain visible")
	_expect(enabled_collision_count == 1, "stairs use one smooth gameplay collider")

	var player := PlayerScene.instantiate() as CharacterBody3D
	_expect(player != null, "the real SocomTestPlayer scene instantiates")
	if player == null:
		_finish()
		return
	player.name = "StairTraversalPlayer"
	player.position = Vector3(0.0, 0.05, LOWER_STOP_Z + 0.8)
	player.set_local_input_enabled(false)
	player.set("automatic_vault_enabled", false)
	world.add_child(player)
	await _step_physics(12)
	_expect(player.is_on_floor(), "player starts grounded on the lower landing")

	var ascent_grounded_frames := 0
	var ascent_frames := 0
	var ascent_peak := player.global_position.y
	for _frame in range(MAX_TRAVEL_FRAMES):
		_queue_world_direction(player, Vector3.FORWARD)
		await physics_frame
		ascent_frames += 1
		ascent_peak = maxf(ascent_peak, player.global_position.y)
		if player.is_on_floor():
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
		descent_low = minf(descent_low, player.global_position.y)
		if player.is_on_floor():
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
