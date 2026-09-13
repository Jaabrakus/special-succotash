extends "res://tools/ledge_climb_regression.gd"

var runtime_main: Node3D
var narrow_driver: Node
var narrow_weapon: Node
var maximum_shuffle_speed := 0.0
var held_command = Command.new()

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/selected_map_document", load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	root.size = Vector2i(1280,800)
	runtime_main = load("res://main.tscn").instantiate() as Node3D
	root.add_child(runtime_main)
	for frame in 90:
		await physics_frame
		await process_frame
	player = runtime_main.get_node("Player")
	player.set_local_input_enabled(false)
	physics_frame.connect(_feed_held_command)
	narrow_weapon = runtime_main.get_node("WeaponController")
	narrow_weapon.set_input_enabled(false)
	narrow_driver = player.get_node("Mannequin/ProductionAnimation")
	world = Node3D.new()
	root.add_child(world)
	world.position = Vector3(500,0,500)
	_box("NarrowProofFloor", Vector3(20,0.2,20), Vector3(0,-0.1,0))
	_box("NarrowProofTop", Vector3(5,2.55,1.15), Vector3(0,1.275,-0.075))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-30,0)
	world.add_child(light)
	camera = Camera3D.new()
	world.add_child(camera)
	_expect(narrow_driver.has_method("_advance_traversal_presentation"), "canonical animation driver compiled and loaded")
	if not narrow_driver.has_method("_advance_traversal_presentation"):
		await _finish()
		return
	_expect(player.traversal.has_method("is_narrow_walking"), "canonical runtime exposes narrow mode")
	if not player.traversal.has_method("is_narrow_walking"):
		await _finish()
		return
	await _reset(Vector3(500,0.03,501.35))
	_expect(not bool(_probe().get("accepted", false)), "tall ledge is beyond grounded fingertips")
	var takeoff := player.global_position
	await _step(true,true)
	var airborne_before_grab := false
	for frame in 45:
		await _step(false,true)
		airborne_before_grab = airborne_before_grab or (not player.is_on_floor() and player.global_position.y > takeoff.y+0.05)
		if frame == 1: await _capture("jump-approach")
		if player.traversal.is_hanging(): break
	_expect(airborne_before_grab and player.traversal.is_hanging(), "physical jump catches supported narrow ledge")
	if not player.traversal.is_hanging():
		await _finish()
		return
	for frame in 12: await _step(false,false,false,-1)
	_expect(player.traversal.is_hanging(), "held forward cannot skip initial hang")
	for frame in 20: await _step()
	var hanging := player.global_position
	for frame in 12: await _step()
	_expect(player.traversal.is_hanging() and player.global_position.distance_to(hanging)<0.01, "stable hang waits for fresh climb input")
	await _capture("hang")
	await _step(false,false,false,-1)
	_expect(player.traversal.is_mantling(), "fresh W starts validated pull-up")
	var seen_pullup := false
	for frame in 180:
		await _step()
		if player.traversal.is_mantling():
			seen_pullup = true
			if frame == 22: await _capture("pull-up")
		if player.traversal.is_narrow_walking(): break
	_expect(seen_pullup and player.traversal.is_narrow_walking(), "pull-up hands off directly to narrow walking")
	if not player.traversal.is_narrow_walking():
		await _finish()
		return
	for frame in 24: await _step()
	await create_timer(0.0).timeout
	_expect(player.is_on_floor() and player.global_position.y>2.5, "narrow mode stands on collision-supported top")
	_expect(str(player.get_traversal_presentation().get("slot", "")) == "narrow_idle", "idle selects authored narrow pose")
	_expect(str(narrow_driver.clip_paths.get(&"traversal_narrow_idle", "")).ends_with("CMC_NarrowFloor_IdlePoses.scn"), "actual driver loads AGLS narrow idle source")
	_expect(str(narrow_driver.clip_paths.get(&"traversal_pull_up", "")).ends_with("CMC_Climb_To_Standing.scn"), "entry retains calibrated braced pull-up, not unverified narrow-climb clip")
	_verify_narrow_presentation("idle")
	await _capture("idle")
	var idle_position := player.global_position
	var idle_phase := float(player.get_traversal_presentation().get("phase", -1.0))
	var idle_travel := float(player.traversal.state_machine.context.get("travel_metres", -1.0))
	for frame in 30: await _step()
	_expect(player.global_position.distance_to(idle_position)<0.015, "idle holds physical position")
	_expect(is_equal_approx(float(player.get_traversal_presentation().get("phase", -2.0)), idle_phase), "idle phase does not play through pose bank")
	_expect(idle_travel>=0.0 and is_equal_approx(float(player.traversal.state_machine.context.get("travel_metres", -2.0)), idle_travel), "idle does not invent travelled distance")
	var before_right := player.global_position
	for frame in 36:
		await _step(false,false,false,0,false,1)
		maximum_shuffle_speed = maxf(maximum_shuffle_speed, player.velocity.slide(Vector3.UP).length())
		if frame == 18:
			await create_timer(0.0).timeout
			_expect(str(player.get_traversal_presentation().get("slot", "")) == "narrow_right", "D selects authored right shuffle")
			_verify_narrow_presentation("right shuffle")
			await _capture("right-shuffle")
	_expect(player.global_position.x>before_right.x+0.2 and absf(player.global_position.z-before_right.z)<0.02, "D moves along ledge tangent only")
	var after_right := player.global_position
	for frame in 36:
		await _step(false,false,false,0,false,-1)
		maximum_shuffle_speed = maxf(maximum_shuffle_speed, player.velocity.slide(Vector3.UP).length())
		if frame == 18:
			await create_timer(0.0).timeout
			_expect(str(player.get_traversal_presentation().get("slot", "")) == "narrow_left", "A selects authored left shuffle")
			_verify_narrow_presentation("left shuffle")
			await _capture("left-shuffle")
	_expect(player.global_position.x<after_right.x-0.2 and absf(player.global_position.z-after_right.z)<0.02, "A reverses safely along ledge")
	_expect(maximum_shuffle_speed<=0.6001, "actual narrow velocity respects 0.6m/s cap max="+str(maximum_shuffle_speed))
	for frame in 300: await _step(false,false,false,0,false,1)
	var stopped := player.global_position
	for frame in 30: await _step(false,false,false,0,false,1)
	var capsule := player.get_node("CollisionShape3D").shape as CapsuleShape3D
	_expect(player.traversal.is_narrow_walking() and player.is_on_floor(), "holding shuffle at end stays supported")
	_expect(player.global_position.x<=502.5-capsule.radius*0.85+0.01 and player.global_position.distance_to(stopped)<0.015, "end stops before five-point support leaves geometry")
	await _capture("edge-stop")
	await _step()
	var before_jump := player.global_position
	await _step(true,false,false,0,false)
	for frame in 3: await _step()
	_expect(not player.traversal.is_active() and not player.is_on_floor() and player.global_position.y>before_jump.y+0.05, "fresh Jump exits narrow mode into ordinary airborne movement")
	await create_timer(0.0).timeout
	_expect(not narrow_driver.traversal_hand_contact.active, "overhead contact stays cleared on jump exit")
	_expect(narrow_driver.weapon_node.visible and not is_instance_valid(narrow_driver.traversal_stow.visual), "jump exit restores equipped weapon and removes stowed copy")
	await _capture("jump-exit")
	await _finish()

func _verify_narrow_presentation(label: String) -> void:
	var contact = narrow_driver.traversal_hand_contact
	var graph_state: Dictionary = narrow_driver.locomotion_graph.get_debug_state()
	_expect(bool(graph_state.get("modern_enabled", false)) and StringName(graph_state.get("modern_state", &"")) == narrow_driver.current_clip, label+" evaluates the selected narrow traversal state, not ordinary locomotion")
	# The modifier may remain active solely to face the authored pose toward
	# the wall. That is not hand IK: no arm weights, solves or root lift remain.
	_expect(contact.weight == 0.0 and contact.hand_weights == [0.0,0.0] and contact.evaluated_hand_weights == [0.0,0.0] and contact.errors_m.is_empty() and contact.reach_diagnostics.is_empty() and contact.visual_root_delta == Vector3.ZERO, label+" does not reuse overhead hang IK")
	_expect(not narrow_driver.weapon_node.visible and is_instance_valid(narrow_driver.traversal_stow.visual) and narrow_driver.traversal_stow.visual.is_visible_in_tree(), label+" keeps rifle visibly stowed")
	_expect(player.is_fire_locked_by_mobility(), label+" remains mobility fire locked")
	var ammo_before := int(narrow_weapon.rounds_in_magazine)
	var shot: Dictionary = narrow_weapon.request_fire()
	_expect(not bool(shot.get("fired", false)) and str(shot.get("reason", "")) == "MOBILITY_ACTION" and int(narrow_weapon.rounds_in_magazine) == ammo_before, label+" firing is rejected without consuming ammunition")
	var foot_points: Array[Dictionary] = []
	for bone_name: String in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		var index: int = narrow_driver.skeleton.find_bone("mixamorig_"+bone_name)
		_expect(index>=0, label+" has "+bone_name+" landmark")
		if index<0: continue
		var point: Vector3 = narrow_driver.skeleton.to_global(narrow_driver.skeleton.get_bone_global_pose(index).origin)
		foot_points.append({"bone":bone_name, "height_above_top_m":point.y-2.55, "world_point":point})
		# Bone heads are not the mesh soles. This catches gross vertical pose
		# errors; rendered feet still require separate contact inspection.
		_expect(point.is_finite() and point.y-2.55>=-0.08 and point.y-2.55<=0.35, label+" foot landmark has no gross vertical offset "+bone_name)
	print("NARROW_FOOT_LANDMARKS ",label," ",foot_points)
	print("NARROW_GRAPH ",label," clip=",narrow_driver.current_clip," movement=",narrow_driver.movement_state," graph=",graph_state)

func _step(jump: bool = false, held: bool = false, drop: bool = false, axis: float = 0.0, auto_forward: bool = true, lateral: float = 0.0) -> void:
	held_command = Command.new()
	held_command.jump_pressed = jump
	held_command.jump_held = held
	held_command.crouch_held = drop
	held_command.move_axis = Vector2(lateral,axis)
	if auto_forward and (jump or held): held_command.move_axis.y = -1.0
	await physics_frame
	await process_frame

func _feed_held_command() -> void:
	# Rendering may run several physics ticks between captured frames. Keep
	# held inputs continuous, as real keyboard input is; consume press once.
	if paused or not is_instance_valid(player): return
	held_command.simulation_tick = Engine.get_physics_frames()
	player.queue_movement_command(held_command)
	held_command.jump_pressed = false

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await create_timer(0.0).timeout
	var was_paused := paused
	paused = true
	var output := "res://art_source/traversal_runtime_proof"
	DirAccess.make_dir_recursive_absolute(output)
	for side in [-1,1]:
		camera.global_position = player.global_position + Vector3(side*3.4,2.3,3.2)
		camera.look_at(player.global_position+Vector3.UP*1.0)
		camera.make_current()
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		var result := root.get_texture().get_image().save_png(output+"/narrow-"+label+"-side"+str(side)+".png")
		_expect(result == OK, "capture saved "+label+" side="+str(side))
	paused = was_paused

func _finish() -> void:
	physics_frame.disconnect(_feed_held_command)
	runtime_main.queue_free()
	world.queue_free()
	await process_frame
	print("MAIN_NARROW_LEDGE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
