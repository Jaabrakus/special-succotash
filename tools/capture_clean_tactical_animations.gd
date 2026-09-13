extends SceneTree

const GLB_PATH := "res://art_source/clean_tactical_animations/clean_tactical_operator.glb"
const OUT_DIR := "/Users/kiwimango/.gemini/antigravity/brain/f986929c-8da1-4107-a543-f9a5cdef5604"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(800, 800)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(GLB_PATH), state) != OK:
		push_error("FAILED to load GLB")
		quit(1)
		return
	
	var model := document.generate_scene(state) as Node3D
	model.scale = Vector3.ONE * 62.0
	model.rotation.y = PI
	root.add_child(model)
	
	_setup_world()
	
	var anim_player: AnimationPlayer = _find_animation_player(model)
	if anim_player == null:
		push_error("AnimationPlayer not found in GLB")
		quit(1)
		return
		
	print("Found AnimationPlayer with clips: ", anim_player.get_animation_list())
	
	var shots := {
		"clean_aim_idle": {"clip": "rifle_aim_idle", "time": 0.5},
		"clean_lean_left": {"clip": "tactical_lean_left", "time": 0.5},
		"clean_lean_right": {"clip": "tactical_lean_right", "time": 0.5},
		"clean_crouch_idle": {"clip": "crouch_aim_idle", "time": 0.5},
		"clean_walk_forward": {"clip": "rifle_walk_forward", "time": 0.4}
	}
	
	for shot_name in shots:
		var spec: Dictionary = shots[shot_name]
		var clip_name: String = spec.clip
		var seek_time: float = spec.time
		
		anim_player.play(clip_name)
		anim_player.seek(seek_time, true)
		
		for _f in range(4):
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		
		var img := root.get_texture().get_image()
		var out_path := "%s/%s.png" % [OUT_DIR, shot_name]
		if img != null and not img.is_empty():
			img.save_png(out_path)
			print("CAPTURED: ", out_path)
			
	# Capture animated sequence frames
	var frames_dir := "%s/frames" % OUT_DIR
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var sequence_specs := {
		"lean_left": {"clip": "tactical_lean_left", "duration": 1.5, "count": 12},
		"lean_right": {"clip": "tactical_lean_right", "duration": 1.5, "count": 12},
		"aim_idle": {"clip": "rifle_aim_idle", "duration": 3.1, "count": 12},
		"crouch_idle": {"clip": "crouch_aim_idle", "duration": 2.1, "count": 12},
		"walk_forward": {"clip": "rifle_walk_forward", "duration": 1.3, "count": 12}
	}
	for anim_id in sequence_specs:
		var s: Dictionary = sequence_specs[anim_id]
		var clip: String = s.clip
		var dur: float = s.duration
		var count: int = s.count
		anim_player.play(clip)
		for f_idx in range(count):
			var t: float = (float(f_idx) / float(count - 1)) * dur
			anim_player.seek(t, true)
			for _f in range(2):
				await process_frame
			RenderingServer.force_draw()
			await process_frame
			var frame_img := root.get_texture().get_image()
			if frame_img != null and not frame_img.is_empty():
				# Resize to 360x360 for fast web animation rendering
				frame_img.resize(360, 360)
				var frame_path := "%s/%s_%02d.jpg" % [frames_dir, anim_id, f_idx]
				frame_img.save_jpg(frame_path, 0.82)
		print("CAPTURED_SEQUENCE: ", anim_id)
		
	print("ALL_CAPTURES_SUCCESS")
	quit(0)

func _setup_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("2c333a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	light.light_energy = 1.3
	root.add_child(light)
	
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.15, -2.8)
	camera.fov = 42.0
	root.add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	camera.current = true

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
