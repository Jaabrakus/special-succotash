extends SceneTree
## Read-only comparison. Does not run builders, change selection, or edit assets.

const PATHS := {
	"canonical_ps1_fallback":"res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn",
	"modern_selected":"res://assets/characters/modern_soldier/modern_soldier.scn",
	"rejected_iso_candidate":"res://assets/characters/modern_soldier/modern_soldier_iso.scn",
}
const SPANS := {
	"hips_to_lower_spine":["Hips", "Spine"],
	"lower_spine_to_upper_spine":["Spine", "Spine2"],
	"upper_spine_to_neck":["Spine2", "Neck"],
	"neck_to_head":["Neck", "Head"],
	"clavicle_origin_width":["LeftShoulder", "RightShoulder"],
	"shoulder_joint_width":["LeftArm", "RightArm"],
	"hips_to_head":["Hips", "Head"],
	"left_upper_arm":["LeftArm", "LeftForeArm"],
	"left_forearm":["LeftForeArm", "LeftHand"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var report := {"selected":JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_character.json")), "models":{}, "clip_finger_channels":{}}
	var reference: Array[Transform3D] = []
	for label: String in PATHS:
		var model := (load(PATHS[label]) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		model.scale = Vector3.ONE * 62.0
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var spans := {}
		for name: String in SPANS:
			var pair: Array = SPANS[name]
			var a := skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_" + pair[0])).origin
			var b := skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_" + pair[1])).origin
			spans[name] = (skeleton.global_basis * (a-b)).length()
		var rest_changed := 0
		var orientation_changed := 0
		for bone in skeleton.get_bone_count():
			if label == "canonical_ps1_fallback": reference.append(skeleton.get_bone_rest(bone))
			else:
				if not skeleton.get_bone_rest(bone).is_equal_approx(reference[bone]): rest_changed += 1
				if not skeleton.get_bone_rest(bone).basis.is_equal_approx(reference[bone].basis): orientation_changed += 1
		var maximum_bind_translation := 0.0
		var maximum_bind_basis := 0.0
		var bind_count := 0
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.skin == null: continue
			for bind in mesh.skin.get_bind_count():
				var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0: bone = mesh.skin.get_bind_bone(bind)
				assert(bone >= 0)
				var residual := skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind)
				maximum_bind_translation = maxf(maximum_bind_translation, (skeleton.global_basis * residual.origin).length())
				maximum_bind_basis = maxf(maximum_bind_basis, maxf((residual.basis.x-Vector3.RIGHT).length(), maxf((residual.basis.y-Vector3.UP).length(), (residual.basis.z-Vector3.BACK).length())))
				bind_count += 1
		report.models[label] = {"path":PATHS[label],"sha256":FileAccess.get_sha256(PATHS[label]),
			"iso_proportions":skeleton.has_meta("iso_proportions"),"bones":skeleton.get_bone_count(),
			"changed_local_rests":rest_changed,"changed_local_rest_orientations":orientation_changed,
			"spans_m":spans,"skin_binds_checked":bind_count,
			"maximum_bind_translation_residual_m":maximum_bind_translation,"maximum_bind_basis_residual":maximum_bind_basis}
		model.free()
	for path in ["res://assets/animations/seal_reference/seal_p_run.tres", "res://assets/animations/seal_gameplay/pistol_run_forward.tres", "res://assets/animations/seal_firing_reference/seal_pfp_run.tres"]:
		if not ResourceLoader.exists(path): continue
		var clip := load(path) as Animation
		var fingers := []
		for track in clip.get_track_count():
			var bone := str(clip.track_get_path(track))
			if "Thumb" in bone or "Index" in bone or "Middle" in bone or "Ring" in bone or "Pinky" in bone:
				fingers.append(bone)
		report.clip_finger_channels[path] = fingers
	print("SOURCE_RIG_SELECTION_AUDIT ", JSON.stringify(report))
	quit()
