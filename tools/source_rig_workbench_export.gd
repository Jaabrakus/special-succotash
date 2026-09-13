extends SceneTree
## Offline six-clip interchange proof. No runtime profile or asset is changed.

const MODEL := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
const CLIPS := {
	"stand": "res://assets/animations/seal_reference/seal_stand_alert02.tres",
	"run": "res://assets/animations/seal_reference/seal_run.tres",
	"walk": "res://assets/animations/seal_reference/seal_walk.tres",
	"strafe_left": "res://assets/animations/seal_reference/seal_lstrafe.tres",
	"strafe_right": "res://assets/animations/seal_reference/seal_rstrafe.tres",
	"pistol_run": "res://assets/animations/seal_gameplay/pistol_run_forward.tres",
}

func _initialize() -> void:
	call_deferred("_run")

func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var result := _find(child, type)
		if result != null: return result
	return null

func _matrix(transform: Transform3D) -> Array:
	return [
		[transform.basis.x.x, transform.basis.y.x, transform.basis.z.x, transform.origin.x],
		[transform.basis.x.y, transform.basis.y.y, transform.basis.z.y, transform.origin.y],
		[transform.basis.x.z, transform.basis.y.z, transform.basis.z.z, transform.origin.z],
		[0.0, 0.0, 0.0, 1.0],
	]

func _poses(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for index in skeleton.get_bone_count():
		result[skeleton.get_bone_name(index)] = _matrix(skeleton.global_transform * skeleton.get_bone_global_pose(index))
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.dir_exists_absolute(args[0]):
		push_error("Supply one NEW absolute output directory. Refusing to overwrite.")
		quit(1)
		return
	var out := str(args[0])
	assert(out.is_absolute_path())
	assert(DirAccess.make_dir_recursive_absolute(out) == OK)
	var scene := Node3D.new()
	scene.name = "SourceRigReview"
	root.add_child(scene)
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	scene.add_child(model)
	model.scale = Vector3.ONE * 62.0
	model.rotation.y = PI
	var skeleton := _find(model, "Skeleton3D") as Skeleton3D
	assert(skeleton != null)
	for previous in model.find_children("*", "AnimationPlayer", true, false): previous.free()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null: mesh.free()
	skeleton.reset_bone_poses()
	var rest := _poses(skeleton)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(scene, state) == OK)
	assert(document.write_to_filesystem(state, out.path_join("rest_character.glb")) == OK)
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	player.add_animation_library("", library)
	var rows := []
	for key: String in CLIPS:
		var clip := (load(CLIPS[key]) as Animation).duplicate(true) as Animation
		var loops := clip.loop_mode
		clip.loop_mode = Animation.LOOP_NONE
		library.add_animation(key, clip)
		var samples := []
		# Exact authored key times, rather than an unrelated fixed-rate rebake.
		var sample_times: Array[float] = [0.0, clip.length]
		for track in clip.get_track_count():
			for index in clip.track_get_key_count(track):
				var time := clip.track_get_key_time(track, index)
				if not sample_times.has(time): sample_times.append(time)
		sample_times.sort()
		for time in sample_times:
			player.stop()
			skeleton.reset_bone_poses()
			player.play(key)
			player.seek(time, true)
			player.advance(0.0)
			samples.append({"time":time, "bones":_poses(skeleton)})
		var between_keys := []
		for index in sample_times.size() - 1:
			var time := (sample_times[index] + sample_times[index + 1]) * 0.5
			player.stop()
			skeleton.reset_bone_poses()
			player.play(key)
			player.seek(time, true)
			player.advance(0.0)
			between_keys.append({"time":time, "bones":_poses(skeleton)})
		rows.append({"name":key,"path":CLIPS[key],"resource_sha256":FileAccess.get_sha256(CLIPS[key]),
			"source_name":clip.get_meta("source_name", ""),"source_sha256":clip.get_meta("source_sha256", ""),
			"coverage":clip.get_meta("source_coverage", ""),"composite_base":clip.get_meta("seal_composite_base", ""),
			"length":clip.length,"loop_mode":loops,"samples":samples,"between_key_validation":between_keys})
	player.stop()
	skeleton.reset_bone_poses()
	var file := FileAccess.open(out.path_join("pose_samples.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"engine":Engine.get_version_info(),
		"stage":"character-retarget reference, before runtime procedural modifiers; not source-engine parity",
		"model":MODEL,"model_sha256":FileAccess.get_sha256(MODEL),"rest_bones":rest,"clips":rows}, "\t"))
	file.close()
	print("SOURCE_RIG_WORKBENCH_EXPORT_PASS clips=",rows.size()," bones=",skeleton.get_bone_count()," output=",out)
	scene.queue_free()
	await process_frame
	quit()
