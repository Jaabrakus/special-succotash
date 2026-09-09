extends "res://tools/agls_ak47_retarget_visual_check.gd"

## Asset-only trial, reusing the same adapter called by operator_asset_runtime.
const OUTPUT := "res://art_source/ps1_agls_trial"


func _finish() -> void:
	if not failures.is_empty():
		super._finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var actor := root.get_node("AK47ReloadRetargetProof/ReloadPose_0") as Node3D
	var skeleton := _find_skeleton(actor)
	var player := skeleton.get_node("AK47ReloadPosePlayer") as AnimationPlayer
	var clip := player.get_animation(&"reload_ak47")
	_expect(clip.get_track_count() > 20, "retarget has body animation tracks")
	for track in clip.get_track_count():
		var bone := String(clip.track_get_path(track)).get_slice(":", 1)
		_expect(skeleton.find_bone(bone) >= 0, "track resolves: " + bone)
	actor.position = Vector3.ZERO
	player.stop()
	skeleton.reset_bone_poses()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	_expect(document.append_from_scene(actor, state) == OK, "GLB scene conversion")
	_expect(document.write_to_filesystem(state, OUTPUT + "/ps1_agls_reload_trial.glb") == OK, "animated GLB saved")
	var report := {
		"scope": "isolated asset trial; no runtime replacement",
		"source_clip": RELOAD_PATH,
		"target": TARGET_PATH,
		"target_bones": skeleton.get_bone_count(),
		"tracks": clip.get_track_count(),
		"duration_seconds": clip.length,
		"limitations": ["no weapon attached", "extra finger bones have no new mesh weights", "full animation library not tested"],
		"passed": failures.is_empty(),
	}
	var file := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	for image_path in [FRONT_OUTPUT_PATH, REAR_OUTPUT_PATH]:
		DirAccess.copy_absolute(image_path, ProjectSettings.globalize_path(OUTPUT.path_join(image_path.get_file())))
	super._finish()
