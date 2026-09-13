extends SceneTree

const PlayerScene := preload("res://scenes/player/operator_player.tscn")
const Command := preload("res://scripts/network/socom_movement_command.gd")
const Codec := preload("res://scripts/network/socom_movement_state.gd")
const Ladder := preload("res://scenes/traversal/climbable_ladder.tscn")
const NetworkOperator := preload("res://scripts/network/socom_network_operator.gd")
var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_box("Floor", Vector3(100, 0.2, 100), Vector3(0, -0.1, 0))
	var ledge := _box("Platform", Vector3(3, 2.0, 4), Vector3(0, 1, -1.5))
	player = PlayerScene.instantiate()
	player.set_local_input_enabled(false)
	world.add_child(player)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	world.add_child(light)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5, 3.5, 5)
	camera.look_at(Vector3(0, 1.3, 0))
	await _reset(Vector3(0, 0.03, 1.35))
	var driver = player.get_node("Mannequin/ProductionAnimation")
	for clip_name in player.traversal.mantle_motor.climb_profile.presentation_clips.values():
		var clip: Animation = driver.animation_player.get_animation(clip_name)
		_expect(clip != null, "dedicated clip loaded: " + str(clip_name))
		if clip == null: continue
		var hips := clip.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		var anchored := hips >= 0
		if hips >= 0:
			var reference: Vector3 = clip.track_get_key_value(hips, 0)
			for key in clip.track_get_key_count(hips):
				anchored = anchored and reference.is_equal_approx(clip.track_get_key_value(hips, key))
		_expect(anchored, "no duplicate hip lift: " + str(clip_name))
	await _step(true, true)
	_expect(player.traversal.is_hanging(), "Jump grabs before climbing")
	for frame in 10: await _step(false, false, false, -1.0)
	_expect(player.traversal.is_hanging(), "held forward cannot skip hang")
	await _step()
	await _step(false, false, false, -1.0)
	_expect(player.traversal.is_mantling(), "fresh W starts pull-up")
	_expect(player.is_fire_locked_by_mobility(), "pull-up occupies weapon hands")
	_expect(player.get_traversal_presentation().get("slot") == "pull_up", "pull-up selects dedicated presentation")
	for frame in 110:
		await _step()
		if frame == 18: await _capture("pullup")
	_expect(player.global_position.y > 1.95 and player.is_on_floor(), "climb lands on platform")
	_expect(player.global_position.z < 0.2, "body moves across ledge after rising")
	await _capture("landed")
	# Geometry policy: same static surface, no animation or display-name guesses.
	await _reset(Vector3(0, 0.03, 1.35))
	ledge.add_to_group("no_climb")
	_expect(not _probe().get("accepted", false), "no_climb opt-out rejects platform")
	_expect(not player._try_begin_automatic_vault(Vector3.FORWARD, true, true), "fresh tap respects no_climb")
	ledge.remove_from_group("no_climb")
	player.traversal.mantle_motor.climb_profile.require_climbable_group = true
	_expect(not _probe().get("accepted", false), "tag-only policy rejects untagged platform")
	ledge.add_to_group("climbable")
	_expect(_probe().get("accepted", false), "tag-only policy accepts tagged platform")
	player.traversal.mantle_motor.climb_profile.require_climbable_group = false
	var ceiling := _box("Ceiling", Vector3(4, 0.2, 4), Vector3(0, 3, 0.5))
	await physics_frame
	var blocked_top := _probe()
	_expect(bool(blocked_top.get("accepted",false)) and not bool(blocked_top.get("can_pull_up",true)), "standing overhead blockage may retain safe grip only")
	_expect(player._try_begin_automatic_vault(Vector3.FORWARD, true, true) and player.traversal.is_hanging(), "fresh tap can hang below standing overhead blocker")
	for frame in 20: await _step()
	_expect(not player.traversal.pull_up(player) and player.traversal.is_hanging(), "overhead blocker never permits unsafe pull-up")
	player.traversal.leave_grip()
	ceiling.queue_free()
	await physics_frame
	ledge.position.y += 0.55
	# A second tap must climb, not require holding Jump or full movement input.
	for tap_axis in [0.0, -0.25, -1.0]:
		await _reset(Vector3(0, 0.03, 1.35))
		await _step(true, false)
		for frame in 25:
			await _step(false, false, false, -1.0)
			if _probe().get("accepted", false): break
		_expect(_probe().get("accepted", false), "second-tap fixture is within physical reach")
		player.automatic_vault_retry_remaining = 0.5
		_expect(not player._try_begin_automatic_vault(Vector3.FORWARD, true, true), "fresh tap respects detach cooldown")
		player.automatic_vault_retry_remaining = 0.0
		player.automatic_vault_probe_remaining = 0.08
		await _step(true, false, false, tap_axis, false)
		_expect(player.traversal.is_hanging(), "second tap grabs despite probe timer, axis=" + str(tap_axis))
		await _step()
		await _step(false, false, false, -1.0)
		_expect(player.traversal.is_mantling(), "fresh W pulls up after tap grab")
		for frame in 110:
			await _step()
			if tap_axis == 0.0 and frame in [5, 25, 55]: await _capture("tap-" + str(frame))
		_expect(player.is_on_floor() and player.global_position.y > 2.5, "second tap lands on ledge, axis=" + str(tap_axis))
	await _reset(Vector3(0, 0.03, 1.35))
	_expect(not _probe().get("accepted", false), "2.55m ledge is beyond grounded fingertips")
	_expect(not player._try_begin_automatic_vault(Vector3.FORWARD, true, true), "fresh tap cannot bypass physical reach")
	await _step(true, true)
	var caught := false
	for frame in 45:
		await _step(false, true)
		if player.traversal.is_hanging():
			caught = true
			break
	_expect(caught, "physical jump extends reach and catches ledge")
	if caught:
		_expect(player.is_fire_locked_by_mobility(), "hang occupies weapon hands")
		_expect(player.get_traversal_presentation().get("slot") == "hang", "hang selects stable dedicated pose")
		var proxy := NetworkOperator.new()
		proxy.is_proxy_replica = true
		proxy._apply_snapshot_presentation({"presentation": {"traversal": player.get_traversal_presentation()}})
		_expect(proxy.get_traversal_presentation().get("slot") == "hang", "remote proxy receives hang presentation")
		proxy._apply_snapshot_presentation({"presentation": {}})
		_expect(proxy.get_traversal_presentation().is_empty(), "remote proxy clears traversal after exit")
		proxy.free()
		for frame in 20: await _step()
		var held := player.global_position
		for frame in 20: await _step()
		_expect(held.distance_to(player.global_position) < 0.01, "hang holds without falling")
		var state := Codec.unpack(Codec.pack(Codec.capture(player)))
		_expect(not state.is_empty(), "hang state fits network codec")
		Codec.apply(player, state)
		_expect(player.traversal.is_hanging(), "replayed hang keeps anchor and mode")
		await _capture("hang")
		var before_shimmy := player.global_position
		for frame in 30: await _step(false, false, false, 0, false, 1)
		_expect(player.global_position.x > before_shimmy.x + 0.2, "D shimmies right")
		for frame in 30: await _step(false, false, false, 0, false, -1)
		_expect(absf(player.global_position.x - before_shimmy.x) < 0.08, "A shimmies left")
		for frame in 180: await _step(false, false, false, 0, false, 1)
		var hand_margin := float(player.traversal.mantle_motor.climb_profile.get("grip_half_width_m",0.19))
		_expect(player.traversal.is_hanging() and player.global_position.x <= 1.5-hand_margin+0.001 and player.global_position.x > 0.5, "shimmy stops before unsupported hand grip")
		for frame in 180: await _step(false, false, false, 0, false, -1)
		await _step(true, false)
		_expect(player.traversal.is_mantling(), "fresh Jump pulls up from hang")
		for frame in 110: await _step()
		_expect(player.global_position.y > 2.5 and player.is_on_floor(), "hang pull-up lands safely")
	await _reset(Vector3(0, 0.03, 1.35))
	await _step(true, true)
	for frame in 45:
		await _step(false, true)
		if player.traversal.is_hanging(): break
	await _step(false, false, false, 1)
	_expect(not player.traversal.is_active(), "S drops ledge hang")
	ledge.position.y += 0.65
	await _reset(Vector3(0, 0.03, 1.35))
	await _step(true, true)
	for frame in 50: await _step(false, true)
	_expect(not player.traversal.is_active(), "jump cannot reach 3.2m ledge")
	ledge.queue_free()
	await physics_frame
	var awning := _box("ThinAwning", Vector3(3, 0.06, 4), Vector3(0, 2.0, -1.5))
	await _reset(Vector3(0, 0.03, 1.35))
	_expect(_probe().get("accepted", false), "thin awning has reachable supported edge")
	await _step(true, true)
	_expect(player.traversal.is_hanging(), "awning grabs into hang")
	await _step()
	await _step(false, false, false, -1)
	for frame in 110: await _step()
	_expect(player.is_on_floor() and player.global_position.y > 2.0, "awning pull-up completes")
	_expect(not player.traversal.is_active() and player.get_traversal_presentation().slot == "", "completed climb exits presentation without replay")
	awning.queue_free()
	await physics_frame
	# Explicit authored ladder plus a top platform at the exit marker.
	_box("LadderPlatform", Vector3(3, 3, 4), Vector3(0, 1.5, -2))
	var ladder := Ladder.instantiate()
	world.add_child(ladder)
	await _reset(Vector3(0, 0.03, 1.35))
	await _step(true, true)
	_expect(player.traversal.is_on_ladder(), "Jump toward authored ladder attaches")
	_expect(player.is_fire_locked_by_mobility(), "ladder occupies weapon hands")
	for frame in 80: await _step(false, false, false, -1.0)
	_expect(player.global_position.y > 1.3, "forward climbs ladder")
	var ladder_state := Codec.unpack(Codec.pack(Codec.capture(player)))
	Codec.apply(player, ladder_state)
	_expect(player.traversal.is_on_ladder(), "ladder progress survives replay")
	await _capture("ladder")
	var before_slide := player.global_position.y
	await _step(true, true)
	for frame in 23: await _step(false, true)
	_expect(player.traversal.is_on_ladder() and player.global_position.y < before_slide - 0.45, "hold Jump slides down without detaching")
	_expect(player.get_traversal_presentation().get("slot") == "ladder_slide", "held Jump selects dedicated slide pose")
	await _step()
	var stopped := player.global_position.y
	for frame in 12: await _step()
	_expect(absf(player.global_position.y - stopped) < 0.02, "release slide grips ladder")
	for frame in 30: await _step(false, false, false, 1.0)
	_expect(player.global_position.y < 1.6, "backward descends ladder")
	for frame in 170:
		await _step(false, false, false, -1.0)
		if not player.traversal.is_active(): break
	_expect(not player.traversal.is_active() and player.global_position.y > 2.9, "top exit dismounts onto platform")
	await _reset(Vector3(0, 0.03, 1.35))
	await _step(true, true)
	await _step()
	await _step(true)
	await _step()
	_expect(not player.traversal.is_active(), "tap Jump releases ladder")
	world.queue_free()
	await process_frame
	print("LEDGE_CLIMB_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _probe() -> Dictionary:
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	return player.traversal.mantle_motor.probe_climb(player, Vector3.FORWARD, shape.height, shape.radius)

func _reset(point: Vector3) -> void:
	player.traversal.leave_grip()
	player.global_position = point
	player.velocity = Vector3.ZERO
	player.posture = player.MotionState.STANDING
	player.motion_state = player.MotionState.STANDING
	player.automatic_vault_retry_remaining = 0.0
	player.automatic_vault_probe_remaining = 0.0
	for frame in 12: await _step()

func _step(jump: bool = false, held: bool = false, drop: bool = false, axis: float = 0.0, auto_forward: bool = true, lateral: float = 0.0) -> void:
	var command := Command.new()
	command.simulation_tick = Engine.get_physics_frames()
	command.jump_pressed = jump
	command.jump_held = held
	command.crouch_held = drop
	command.move_axis = Vector2(lateral, axis)
	if auto_forward and (jump or held): command.move_axis.y = -1.0
	player.queue_movement_command(command)
	await physics_frame
	await process_frame

func _box(label: String, size: Vector3, point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	body.add_child(mesh)
	world.add_child(body)
	return body

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/ledge-" + label + ".png")

func _expect(ok: bool, label: String) -> void:
	print("LEDGE_CHECK ", "PASS " if ok else "FAIL ", label, " position=", player.global_position)
	if not ok: failures.append(label)
