extends SceneTree

## Visual acceptance proof for the AK-specific AGLS reload on the exact
## canonical production skeleton. Five frozen samples make shoulder or wrist
## distortion visible before the clip is allowed into the shared map.

const REAR_OUTPUT_PATH := "/private/tmp/socom-agls-ak47-reload-retarget-rear.png"
const FRONT_OUTPUT_PATH := "/private/tmp/socom-agls-ak47-reload-retarget-front.png"
const TARGET_PATH := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const TARGET_TEXTURE_PATH := "res://assets/characters/ps1_gas_mask_soldier/trooper.png"
const RELOAD_PATH := (
	"res://assets/external/agls_intake/imported/weapon_reload/"
	+ "ALSP2_Reloading_Rifle_AK47.scn"
)
const NativeRigAdapter := preload("res://scripts/player/operator_native_rig_adapter.gd")
const SkeletonContract := preload("res://scripts/player/operator_skeleton_contract.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	stage.name = "AK47ReloadRetargetProof"
	root.add_child(stage)
	_build_environment(stage)
	var target_path := TARGET_PATH
	var source_path := RELOAD_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--target="):
			target_path = argument.trim_prefix("--target=")
		if argument.begins_with("--source="):
			source_path = argument.trim_prefix("--source=")
	var source_root := (load(source_path) as PackedScene).instantiate()
	stage.add_child(source_root)
	source_root.visible = false
	var source_skeleton := _find_skeleton(source_root)
	var source_player := _find_animation_player(source_root)
	_expect(source_skeleton != null and source_player != null, "AK reload source loads")
	if source_skeleton == null or source_player == null:
		_finish()
		return
	var source_name := _first_authored_animation(source_player)
	var source_animation := source_player.get_animation(source_name)
	var target_texture := load(TARGET_TEXTURE_PATH) as Texture2D
	var sample_times: Array[float] = [0.0, 0.75, 1.50, 2.25, 3.0]
	for sample_index in sample_times.size():
		var target_root := (load(target_path) as PackedScene).instantiate() as Node3D
		target_root.name = "ReloadPose_%d" % sample_index
		target_root.position = Vector3((float(sample_index) - 2.0) * 1.18, 0.0, 0.0)
		target_root.rotation.y = PI
		target_root.scale = Vector3.ONE * 62.0
		stage.add_child(target_root)
		_apply_review_material(target_root, target_texture, sample_index)
		var target_skeleton := _find_skeleton(target_root)
		_expect(target_skeleton != null, "canonical target %d loads" % sample_index)
		if target_skeleton == null:
			continue
		SkeletonContract.ensure_65_bones(target_skeleton)
		_stop_animation_players(target_root)
		var retargeted := NativeRigAdapter.adapt_animation_rest_aware(
			source_animation,
			source_skeleton,
			target_skeleton,
			NodePath(".")
		)
		var pose_player := AnimationPlayer.new()
		pose_player.name = "AK47ReloadPosePlayer"
		pose_player.root_node = NodePath("..")
		target_skeleton.add_child(pose_player)
		var library := AnimationLibrary.new()
		library.add_animation(&"reload_ak47", retargeted)
		pose_player.add_animation_library("", library)
		pose_player.play(&"reload_ak47")
		pose_player.seek(sample_times[sample_index], true)
		pose_player.pause()
		_add_pose_label(stage, target_root.position + Vector3(0.0, 2.15, 0.0), sample_times[sample_index])
	var title := Label3D.new()
	title.text = "AK-47 AGLS reload -> canonical operator   0.00 / 0.75 / 1.50 / 2.25 / 3.00 s"
	title.font_size = 44
	title.outline_size = 7
	title.position = Vector3(0.0, 2.62, 0.0)
	title.modulate = Color(0.82, 0.94, 1.0)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stage.add_child(title)
	var camera := Camera3D.new()
	camera.name = "AK47ProofCamera"
	camera.position = Vector3(0.0, 1.28, 8.2)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.05, 0.0), Vector3.UP)
	camera.fov = 40.0
	camera.current = true
	stage.add_child(camera)
	await _frames(8)
	_capture(REAR_OUTPUT_PATH)
	camera.position = Vector3(0.0, 1.28, -8.2)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.05, 0.0), Vector3.UP)
	await _frames(4)
	_capture(FRONT_OUTPUT_PATH)
	_finish()


func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "%s proof renders" % path.get_file())
	if image != null and not image.is_empty():
		_expect(image.save_png(path) == OK, "%s proof is saved" % path.get_file())


func _build_environment(stage: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.045, 0.065)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.69, 0.82)
	environment.ambient_light_energy = 1.15
	world_environment.environment = environment
	stage.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.91, 0.80)
	key.light_energy = 2.2
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	fill.light_color = Color(0.46, 0.67, 1.0)
	fill.light_energy = 1.35
	stage.add_child(fill)
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(7.2, 0.04, 2.2)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.04, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.10, 0.13, 0.18)
	floor.material_override = floor_material
	stage.add_child(floor)


func _apply_review_material(node: Node, texture: Texture2D, sample_index: int) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = Color(0.76, 0.86, 1.0).lerp(
			Color(1.0, 0.76, 0.50), float(sample_index) / 8.0
		)
		material.roughness = 0.88
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_review_material(child, texture, sample_index)


func _add_pose_label(stage: Node3D, position: Vector3, sample_time: float) -> void:
	var label := Label3D.new()
	label.text = "%.2f s" % sample_time
	label.font_size = 34
	label.outline_size = 6
	label.modulate = Color(0.94, 0.97, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position
	stage.add_child(label)


func _stop_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		(node as AnimationPlayer).stop()
		(node as AnimationPlayer).process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_stop_animation_players(child)


func _first_authored_animation(player: AnimationPlayer) -> StringName:
	for animation_name in player.get_animation_list():
		if animation_name != &"RESET":
			return animation_name
	return &""


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_AK47_VISUAL_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_AK47_VISUAL_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_AK47_RETARGET_VISUAL_CHECK PASS rear=%s front=%s" % [
			REAR_OUTPUT_PATH, FRONT_OUTPUT_PATH,
		])
		quit(0)
	else:
		print("AGLS_AK47_RETARGET_VISUAL_CHECK FAIL %s" % [failures])
		quit(1)
