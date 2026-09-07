extends "res://tools/rifle_reference_visual_probe.gd"

const Command := preload("res://scripts/network/socom_movement_command.gd")
const Protocol := preload("res://scripts/network/socom_network_protocol.gd")
const Intent := preload("res://scripts/player/jump_direction_combo_intent.gd")
const NetworkScene := preload("res://scenes/player/network_operator.tscn")
const Encoder := preload("res://scripts/network/socom_snapshot_encoder.gd")
var tick_id: int = 0

func _run() -> void:
	output_prefix = "/private/tmp/jump_direction_combo_regression"
	_test_recognizer()
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	_install_fixture()
	player.set_physics_process(false)
	player.set_local_input_enabled(false)
	player.automatic_vault_enabled = false
	await _reset_player()
	if "--crouch-only" in OS.get_cmdline_user_args():
		await _test_crouched_actions()
		await _test_network()
		print("CROUCHED_DIVE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
		_finish()
		return
	if "--capture-only" in OS.get_cmdline_user_args():
		await _capture_combos()
		_finish()
		return
	await _tick(0, true)
	for frame in 42:
		await _tick(2) # Holding A is only air steering.
	_check(player.mobility_combo_kind == &"", "Normal jump plus held direction stays a jump")
	for entry in [[1, &"slide"], [2, &"left"], [4, &"right"], [8, &"back"]]:
		await _reset_player()
		await _sequence(int(entry[0]))
		var kind := StringName(entry[1])
		if kind == &"slide":
			_check(player.is_on_floor(), "Slide begins on floor")
		_check(player.mobility_combo_kind == kind, "Selected " + String(kind))
		var origin := player.global_position
		var fixed_direction: Vector3 = player.action_direction
		for frame in 18:
			await _tick()
		_check(player.mobility_combo_kind == kind, "No-input preserves committed " + String(kind))
		_check(player.action_direction.is_equal_approx(fixed_direction), "Direction remains committed")
		_check((player.global_position - origin).dot(fixed_direction) > 0.1, "Body travels in selected direction")
		_check(StringName(driver.get("current_clip")) == player.get_mobility_combo_clip(), "Canonical animation matches " + String(kind))
		_check(is_equal_approx(player.get_node("CollisionShape3D").shape.height, 1.25), "Reduced combo collider")
		print("COMBO_CANONICAL ", kind, " clip=", driver.get("current_clip"), " travel=", player.global_position - origin)
		for frame in 115: await _tick()
		if kind in [&"left", &"right"]:
			_check(player.mobility_combo_kind == kind and player.is_on_floor(), "Released movement rests on " + String(kind))
			_check(is_equal_approx(player.action_elapsed, 1.05), "Side-rest holds authored floor pose")
			var head_marker: Node3D = player.get_node("Mannequin").head_marker
			var skeleton: Skeleton3D = driver.get("skeleton")
			var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Head")).origin
			var hips := skeleton.find_bone("mixamorig_Hips")
			var anim_player: AnimationPlayer = driver.get("animation_player")
			var anim := anim_player.get_animation(player.get_mobility_combo_clip())
			var saved_hips := Quaternion.IDENTITY
			for track in anim.get_track_count():
				if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D and String(anim.track_get_path(track)).ends_with(":mixamorig_Hips"):
					saved_hips = anim.rotation_track_interpolate(track, 1.05)
			_check(skeleton.get_bone_pose_rotation(hips).angle_to(saved_hips) < 0.08, "Visible side-rest holds the saved authored floor pose")
			_check(head_world.y - player.global_position.y < 0.9, "Side-rest body stays down, not standing")
			var pelvis_world := skeleton.global_transform * skeleton.get_bone_global_pose(hips).origin
			for side in ["Left", "Right"]:
				var foot_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + side + "Foot")).origin
				print("SIDE_REST_BOOT ", kind, " ", side, " height=", foot_world.y - player.global_position.y, " pelvis=", pelvis_world.y - player.global_position.y)
				_check(foot_world.y < pelvis_world.y + 0.20, "Rest boot stays low: " + String(kind) + side)
			_check(absf(head_marker.position.y - 0.60) < 0.05, "Side-rest camera holds stable head-height envelope")
			var camera_rig := scene.get_node("IndependentCameraRig") as Node3D
			var live_camera: Camera3D = camera_rig.get("camera")
			_check(absf(live_camera.global_basis.x.y) < 0.01, "Camera stays upright during side-rest")
			await _tick(1)
			await _check_recovery_camera(48)
		_check(player.mobility_combo_kind == &"" and player.is_on_floor(), "Grounded recovery for " + String(kind))
		var crouch_exit: bool = kind in [&"slide", &"back"]
		_check(player.posture == (player.MotionState.CROUCHED if crouch_exit else player.MotionState.STANDING), "Expected final stance: " + String(kind))
		_check(is_equal_approx(player.get_node("CollisionShape3D").shape.height, 1.25 if crouch_exit else 1.85), "Expected final collider: " + String(kind))
	await _test_crouch_camera()
	await _test_crouched_actions()
	await _test_chains_and_prone()
	await _test_collision_and_clearance()
	await _test_local_keyboard()
	await _test_network()
	if capture:
		await _capture_combos()
	print("JUMP_DIRECTION_COMBO_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	_finish()

func _test_recognizer() -> void:
	for bit: int in [1, 2, 4, 8]:
		var recognizer := Intent.new()
		_check(recognizer.step(bit, true, 0.016) == &"", "Single tap does not trigger")
		_check(recognizer.step(bit, true, 0.016) == &"", "Holding does not count twice")
		recognizer.step(0, true, 0.10)
		_check(recognizer.step(bit, true, 0.10) == Intent.DIRECTIONS[bit], "Fresh grounded double tap, no Space")
		recognizer.step(0, true, 0.01)
		_check(recognizer.step(bit, true, 0.01) == &"", "Third press does not repeat action")
	var expired := Intent.new()
	expired.step(2, true, 0.01)
	expired.step(0, true, 0.31)
	_check(not expired.armed, "Expired first tap does not suppress auto-vault forever")
	_check(expired.step(2, true, 0.01) == &"", "Expired double tap rejected")
	var mixed := Intent.new()
	mixed.step(2, true, 0.01)
	mixed.step(0, true, 0.01)
	_check(mixed.step(4, true, 0.01) == &"", "Mixed directions rejected")
	mixed.step(0, false, 0.01)
	_check(mixed.step(4, false, 0.01) == &"", "Ineligible airborne/prone state rejects combos")
	var packet := Protocol.movement_to_packet(Command.new())
	packet.direction_held = 32
	_check(not Protocol.movement_packet_is_sane(packet), "Malformed direction mask rejected")
	packet.erase("direction_held")
	_check(Protocol.packet_to_movement(packet).direction_held_mask == 0, "Older clients retain normal movement")

func _reset_player() -> void:
	player.reset_jump_combos()
	player.global_position = Vector3(500, 0.02, 500)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.posture = player.MotionState.STANDING
	player.motion_state = player.MotionState.STANDING
	player._apply_posture_collider()
	for frame in 12: await _tick()

func _tick(mask: int = 0, jump: bool = false, prone: bool = false) -> void:
	await physics_frame
	var command := Command.new()
	tick_id += 1
	command.simulation_tick = tick_id
	command.direction_held_mask = mask
	command.jump_pressed = jump
	command.jump_held = jump
	command.dive_pressed = prone
	command.aim_yaw = 0.0
	command.move_axis = Vector2(float(bool(mask & 4)) - float(bool(mask & 2)), float(bool(mask & 8)) - float(bool(mask & 1)))
	var decoded = Protocol.packet_to_movement(Protocol.movement_to_packet(command))
	_check(decoded.direction_held_mask == mask, "Packet preserves held directions")
	player.queue_movement_command(decoded)
	player._physics_process(1.0 / 60.0)
	await process_frame

func _sequence(bit: int) -> void:
	await _tick()
	await _tick(bit)
	for frame in 3: await _tick()
	await _tick(bit)

func _test_collision_and_clearance() -> void:
	await _reset_player()
	var wall := _obstacle(Vector3(498.9, 1.5, 500), Vector3(0.2, 3, 10))
	await _sequence(2)
	for frame in 110: await _tick()
	_check(player.global_position.x > 499.3, "Side dive cannot pass through wall")
	_check(player.mobility_combo_kind == &"left", "Wall-blocked side dive rests until movement")
	await _tick(1)
	for frame in 48: await _tick()
	_check(player.mobility_combo_kind == &"", "Wall-blocked dive recovers on movement")
	wall.free()
	await _reset_player()
	await _sequence(1)
	for frame in 35: await _tick()
	var roof := _obstacle(player.global_position + Vector3(0, 1.6, 0), Vector3(20, 0.2, 20))
	for frame in 110: await _tick()
	_check(player.posture == player.MotionState.CROUCHED, "Recovery stays crouched under roof")
	_check(is_equal_approx(player.get_node("CollisionShape3D").shape.height, 1.25), "Blocked recovery keeps short collider")
	roof.free()

func _obstacle(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	scene.add_child(body)
	body.global_position = position
	return body

func _test_network() -> void:
	var server := NetworkScene.instantiate() as SocomNetworkOperator
	server.visual_runtime_enabled = false
	server.network_command_driven = true
	scene.add_child(server)
	server.set_physics_process(false)
	server.set_local_input_enabled(false)
	server.global_position = Vector3(510, 0.02, 500)
	server.automatic_vault_enabled = false
	for frame in 35:
		await physics_frame
		var command := Command.new()
		command.simulation_tick = frame
		command.direction_held_mask = 4 if frame in [18, 23] else 0
		server.queue_movement_command(Protocol.packet_to_movement(Protocol.movement_to_packet(command)))
		server._physics_process(1.0 / 60.0)
	_check(server.mobility_combo_kind == &"right", "Independent server consumes DD without Space")
	var proxy := NetworkScene.instantiate() as SocomNetworkOperator
	proxy.visual_runtime_enabled = false
	scene.add_child(proxy)
	proxy.set_replica_mode(true)
	# These represent separate machines; the duplicate must not lift its server.
	server.add_collision_exception_with(proxy)
	var state: Dictionary = Encoder.capture({2: server}, [2])[2]
	proxy.push_network_snapshot(state.position, state.yaw, state.velocity, state.posture, state.health, state.alive, 1.0, state.presentation)
	proxy.update_proxy_interpolation(1.13)
	_check(proxy.get_mobility_combo_clip() == &"jump_dive_right", "Proxy consumes authoritative directional clip")
	_check(is_equal_approx(proxy.action_elapsed, server.action_elapsed), "Proxy receives action phase")
	server.reset_jump_combos()
	server.motion_state = server.MotionState.STANDING
	server.posture = server.MotionState.STANDING
	server._apply_posture_collider()
	for frame in 40:
		await physics_frame
		var command := Command.new()
		command.simulation_tick = frame + 35
		command.direction_held_mask = 1 if frame in [4, 8] else 0
		command.dive_pressed = frame == 20
		server.queue_movement_command(Protocol.packet_to_movement(Protocol.movement_to_packet(command)))
		server._physics_process(1.0 / 60.0)
	state = Encoder.capture({2: server}, [2])[2]
	proxy.push_network_snapshot(state.position, state.yaw, state.velocity, state.posture, state.health, state.alive, 2.0, state.presentation)
	proxy.update_proxy_interpolation(2.13)
	_check(server.combo_exit_prone and proxy.combo_exit_prone, "Server/prone intent reaches proxy")
	_check(proxy.get_mobility_combo_clip() == &"jump_slide_prone", "Proxy selects the shared slide-to-prone asset")
	for bit in [1, 2, 4, 8]:
		server.reset_jump_combos()
		server.global_position = Vector3(510, 0.02, 500)
		server.velocity = Vector3.ZERO
		server._try_set_posture(server.MotionState.CROUCHED)
		server.motion_state = server.MotionState.CROUCHED
		for frame in 25:
			await physics_frame
			var command := Command.new()
			command.simulation_tick = 100 + bit * 30 + frame
			command.direction_held_mask = bit if frame in [4, 8] else 0
			server.queue_movement_command(Protocol.packet_to_movement(Protocol.movement_to_packet(command)))
			server._physics_process(1.0 / 60.0)
		var stamp: float = 3.0 + float(bit)
		state = Encoder.capture({2: server}, [2])[2]
		proxy.push_network_snapshot(state.position, state.yaw, state.velocity, state.posture, state.health, state.alive, stamp, state.presentation)
		proxy.update_proxy_interpolation(stamp + 0.13)
		var expected := &"" if bit == 1 else StringName(server.jump_combo_intent.profile.crouch_clips[String(Intent.DIRECTIONS[bit])])
		print("CROUCH_NETWORK bit=", bit, " expected=", expected, " server=", server.get_mobility_combo_clip(), " proxy=", proxy.get_mobility_combo_clip(), " posture=", server.posture, "/", proxy.posture, " floor=", server.is_on_floor(), " position=", server.global_position)
		_check(server.get_mobility_combo_clip() == expected and proxy.get_mobility_combo_clip() == expected, "Server and proxy agree on crouched action %s" % bit)
	server._set_alive_and_health(false, 0)
	_check(server.mobility_combo_kind == &"" and not server.pending_jump_slide, "Death clears combo")
	server.pending_jump_slide = true
	server.respawn_at(Vector3(510, 0.02, 500))
	_check(not server.pending_jump_slide and not server.jump_combo_intent.armed, "Respawn clears pending combo")
	server.free()
	proxy.free()

func _test_local_keyboard() -> void:
	await _reset_player()
	player.set_local_input_enabled(true)
	for frame in 145:
		await physics_frame
		if frame in [6, 7, 10, 130]:
			var event := InputEventKey.new()
			event.physical_keycode = KEY_A
			event.pressed = frame in [6, 10]
			Input.parse_input_event(event)
		player._physics_process(1.0 / 60.0)
		await process_frame
		if frame == 125:
			_check(player.mobility_combo_kind == &"left" and not player.combo_recovering, "Holding actual second A through landing does not get up")
	_check(player.mobility_combo_kind == &"left", "Actual A/A without Space reaches canonical combo owner")
	player.set_local_input_enabled(false)
	await _tick(2)
	_check(player.combo_recovering, "Fresh movement after release starts get-up")
	await _check_recovery_camera(48)
	await _reset_player()

func _check_recovery_camera(count: int) -> void:
	var mannequin := player.get_node("Mannequin")
	var live_camera: Camera3D = scene.get_node("IndependentCameraRig").get("camera")
	var last_marker_y: float = mannequin.head_marker.position.y
	var last_camera_y: float = live_camera.global_position.y - player.global_position.y
	var worst_marker_drop := 0.0
	var worst_camera_drop := 0.0
	for frame in count:
		await _tick()
		var marker_y: float = mannequin.head_marker.position.y
		var camera_y: float = live_camera.global_position.y - player.global_position.y
		# First few frames allow the prior landing smoothing to settle.
		if frame >= 5:
			worst_marker_drop = maxf(worst_marker_drop, last_marker_y - marker_y)
			worst_camera_drop = maxf(worst_camera_drop, last_camera_y - camera_y)
		last_marker_y = marker_y
		last_camera_y = camera_y
	print("COMBO_CAMERA_RECOVERY max_marker_drop=", worst_marker_drop, " max_lens_drop=", worst_camera_drop)
	_check(worst_marker_drop < 0.015, "Recovery anchor does not dip")
	_check(worst_camera_drop < 0.025, "Recovery gameplay lens does not dip")

func _test_crouch_camera() -> void:
	for bit in [1, 8]:
		await _reset_player()
		await _sequence(bit)
		for frame in 100:
			if player.mobility_combo_kind != &"" and player.action_elapsed >= 1.05:
				break
			await _tick()
		await _check_recovery_camera(70)
		_check(player.posture == player.MotionState.CROUCHED, "Slide/back camera handoff leaves crouch")

func _test_chains_and_prone() -> void:
	for first in [1, 8]:
		for second in [2, 4]:
			await _reset_player()
			await _sequence(first)
			for frame in 16: await _tick()
			await _sequence(second)
			_check(player.mobility_combo_kind == Intent.DIRECTIONS[second], "Longitudinal-to-side chain %s -> %s" % [first, second])
			for frame in 100: await _tick()
			_check(not player.combo_recovering and player.mobility_combo_kind == Intent.DIRECTIONS[second], "Chained side holds at rest")
	await _reset_player()
	await _sequence(1)
	for frame in 18: await _tick()
	await _tick(0, false, true)
	_check(player.combo_exit_prone and player.get_mobility_combo_clip() == &"jump_slide_prone", "Z during slide selects shared prone exit")
	for frame in 115: await _tick()
	_check(player.posture == player.MotionState.PRONE, "Slide finishes prone on request")

func _test_crouched_actions() -> void:
	for bit in [1, 2, 4, 8]:
		await _reset_player()
		player._try_set_posture(player.MotionState.CROUCHED)
		for frame in 45: await _tick()
		var mannequin := player.get_node("Mannequin")
		var entry_height: float = mannequin.head_marker.position.y
		await _sequence(bit)
		if bit == 1:
			_check(player.mobility_combo_kind == &"" and player.posture == player.MotionState.CROUCHED, "Crouched WW stays ordinary crouched travel")
			continue
		_check(player.mobility_combo_kind == Intent.DIRECTIONS[bit], "Crouched action admitted %s" % bit)
		_check(String(player.get_mobility_combo_clip()).begins_with("crouch_dive_"), "Crouched action selects low-entry clip %s" % bit)
		var anim: Animation = driver.animation_player.get_animation(player.get_mobility_combo_clip())
		var idle: Animation = driver.animation_player.get_animation(&"aim_idle_crouch")
		for track in anim.get_track_count():
			if String(anim.track_get_path(track)).ends_with(":mixamorig_Hips") and anim.track_get_type(track) == Animation.TYPE_POSITION_3D:
				var idle_track := idle.find_track(anim.track_get_path(track), Animation.TYPE_POSITION_3D)
				_check(idle_track >= 0 and anim.position_track_interpolate(track, 0.0).distance_to(idle.position_track_interpolate(idle_track, 0.0)) < 0.0001, "Crouched dive starts at actual crouch pelvis %s" % bit)
		var max_entry_height := entry_height
		var lens: Camera3D = scene.get_node("IndependentCameraRig").get("camera")
		var entry_lens_y := lens.global_position.y - player.global_position.y
		var max_lens_y := entry_lens_y
		for frame in 70:
			await _tick()
			max_entry_height = maxf(max_entry_height, mannequin.head_marker.position.y)
			max_lens_y = maxf(max_lens_y, lens.global_position.y - player.global_position.y)
			_check(absf(lens.global_basis.x.y) < 0.01, "Crouched dive camera stays upright %s" % bit)
			if frame == 30:
				_check(driver.locomotion_graph.current_state == player.get_mobility_combo_clip(), "Crouched dive uses actual full-body graph %s" % bit)
		_check(max_entry_height <= entry_height + 0.025, "Crouched dive camera does not pop toward standing %s" % bit)
		_check(max_lens_y <= entry_lens_y + 0.05, "Crouched dive gameplay lens stays low %s" % bit)
		if bit == 8:
			await _check_recovery_camera(70)
			_check(player.posture == player.MotionState.CROUCHED, "Crouched SS returns to crouch")
		else:
			_check(is_equal_approx(player.action_elapsed, 1.05), "Crouched side dive holds on floor %s" % bit)

func _capture_combos() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(960, 640)
	var out := "res://art_source/jump_direction_combos"
	var gameplay_camera: bool = "--gameplay-camera" in OS.get_cmdline_user_args()
	if gameplay_camera:
		out += "/gameplay"
	var crouched_capture: bool = "--crouched" in OS.get_cmdline_user_args()
	if crouched_capture:
		out += "/crouched"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var caption := Label.new()
	caption.position = Vector2(25, 20)
	caption.add_theme_font_size_override("font_size", 24)
	root.add_child(caption)
	var entries := [[1, "WW — KNEE SLIDE"], [2, "AA — LEFT DIVE"], [4, "DD — RIGHT DIVE"], [8, "SS — BACKWARD DIVE"]]
	if "--back-only" in OS.get_cmdline_user_args():
		entries = [[8, "CROUCHED SS — BACKWARD DIVE"]]
	if "--chains-only" in OS.get_cmdline_user_args():
		entries = [[1, "WW → AA", 2], [1, "WW → DD", 4], [8, "SS → AA", 2], [8, "SS → DD", 4], [1, "WW → PRONE", 16]]
	for entry in entries:
		await _reset_player()
		if crouched_capture:
			player._try_set_posture(player.MotionState.CROUCHED)
			for frame in 45: await _tick()
		caption.text = String(entry[1]) + "\nDouble-tap only · release, then move to get up"
		var bit := int(entry[0])
		var folder := out + "/" + str(bit)
		if entry.size() > 2:
			folder += "_" + str(entry[2])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		for frame in 180:
			var mask := bit if frame == 6 or (frame >= 10 and frame <= 90) or frame == 115 else 0
			var request_prone := false
			if entry.size() > 2 and frame >= 30:
				mask = 0
				if int(entry[2]) == 16:
					request_prone = frame == 35
				elif frame == 35 or (frame >= 39 and frame <= 90) or frame == 115:
					mask = int(entry[2])
			await _tick(mask, false, request_prone)
			var focus := player.global_position + Vector3.UP * 0.85
			camera.global_position = focus + Vector3(3.5, 0.9, 3.2)
			camera.look_at(focus)
			if gameplay_camera:
				var live_camera: Camera3D = scene.get_node("IndependentCameraRig").get("camera")
				live_camera.current = true
			else:
				camera.current = true
			RenderingServer.force_draw()
			if frame % 2 == 0:
				var shot := root.get_texture().get_image()
				shot.resize(800, 500, Image.INTERPOLATE_LANCZOS)
				shot.save_png(folder + "/%03d.png" % (frame / 2))
	caption.queue_free()

func _check(value: bool, message: String) -> void:
	if not value and message not in failures:
		failures.append(message)
