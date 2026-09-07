extends SceneTree

const Assets := preload("res://scripts/player/operator_asset_runtime.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const OUT := "res://art_source/jump_peak_slide"
var runtime
var caption: Label

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(960, 640)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("29323d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(16, 16)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("535961")
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	world.add_child(floor_mesh)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5.5, 2.2, 3)
	if "--side" in OS.get_cmdline_user_args():
		camera.position = Vector3(6, 1.6, 0.1)
	if "--right-side" in OS.get_cmdline_user_args():
		camera.position = Vector3(-6, 1.6, 0.1)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.current = true
	caption = Label.new()
	caption.position = Vector2(24, 20)
	caption.add_theme_font_size_override("font_size", 26)
	root.add_child(caption)
	var profile := Profile.new()
	profile.load_project_map()
	var audit_source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			audit_source = argument.trim_prefix("--source=")
			profile.clip_paths[&"source_audit"] = audit_source
	if "--goal" in OS.get_cmdline_user_args():
		profile.clip_paths[&"goalkeeper_source"] = "res://assets/animations/mixamo/Goalkeeper Diving Save.fbx"
	var holder := Node3D.new()
	world.add_child(holder)
	runtime = Assets.new()
	runtime.build(holder, profile, 62.0, Vector3(-0.02, 0.08, 0.05), Vector3(-90, 180, 0))
	var clip: StringName = &"jump_forward_action"
	if not audit_source.is_empty():
		clip = &"source_audit"
	if "--goal" in OS.get_cmdline_user_args():
		clip = &"goalkeeper_source"
	if "--candidate" in OS.get_cmdline_user_args():
		clip = &"jump_peak_slide_candidate"
		if not runtime.animation_player.has_animation(clip):
			var candidate := load("res://assets/animations/authored/jump_peak_slide_candidate.tres") as Animation
			runtime.animation_library.add_animation(clip, candidate)
	if not runtime.animation_player.has_animation(clip):
		push_error("Missing preview clip: " + String(clip))
		quit(1)
		return
	var animation: Animation = runtime.animation_player.get_animation(clip)
	print("SLIDE_SOURCE length=", animation.length, " tracks=", animation.get_track_count())
	runtime.animation_player.play(clip)
	runtime.animation_player.pause()
	for frame in 8:
		await process_frame
	var sheet := Image.create(1440, 600, false, Image.FORMAT_RGB8)
	for index in 6:
		var time := animation.length * float(index) / 5.0
		runtime.animation_player.seek(time, true)
		caption.text = "%s  %.2fs" % [String(clip), time]
		await process_frame
		RenderingServer.force_draw()
		var shot := root.get_texture().get_image()
		shot.convert(Image.FORMAT_RGB8)
		shot.resize(480, 300, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(shot, Rect2i(0, 0, 480, 300), Vector2i((index % 3) * 480, (index / 3) * 300))
		var hips: int = runtime.skeleton.find_bone("mixamorig_Hips")
		print("SLIDE_SOURCE_SAMPLE time=", time, " hips=", runtime.skeleton.get_bone_pose_position(hips), " rotation=", runtime.skeleton.get_bone_pose_rotation(hips))
	var suffix := "_side_sheet.png" if "--side" in OS.get_cmdline_user_args() else "_sheet.png"
	if "--right-side" in OS.get_cmdline_user_args():
		suffix = "_right_side_sheet.png"
	var output_name := audit_source.get_file().get_basename().replace(" ", "_") if not audit_source.is_empty() else String(clip)
	sheet.save_png(OUT + "/" + output_name + suffix)
	world.queue_free()
	caption.queue_free()
	await process_frame
	quit()
