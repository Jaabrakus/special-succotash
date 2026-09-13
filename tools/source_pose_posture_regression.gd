extends SceneTree
## Source-only bypass proof on all 65 bones. Every failed check exits nonzero.

const Posture := preload("res://scripts/player/operator_posture_layer.gd")
const MODEL := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, label: String) -> bool:
	if not condition:
		failures.append(label)
		push_error("SOURCE_POSE_POSTURE_FAIL " + label)
	return condition

func _snapshot(skeleton: Skeleton3D) -> Array:
	var result := []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_global_pose(bone))
	return result

func _expect_unchanged(skeleton: Skeleton3D, before: Array, label: String) -> void:
	for bone in skeleton.get_bone_count():
		_expect(skeleton.get_bone_global_pose(bone).is_equal_approx(before[bone]),
			label + " " + skeleton.get_bone_name(bone))

func _has_change(skeleton: Skeleton3D, before: Array) -> bool:
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_global_pose(bone).is_equal_approx(before[bone]):
			return true
	return false

func _run() -> void:
	var packed := load(MODEL) as PackedScene
	if not _expect(packed != null, "canonical model available"):
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not _expect(not skeletons.is_empty(), "canonical Skeleton3D available"):
		model.queue_free()
		quit(1)
		return
	var skeleton := skeletons[0] as Skeleton3D
	_expect(skeleton.get_bone_count() == 65, "current character uses 65-bone contract")
	skeleton.reset_bone_poses()
	var layer := Posture.new()
	layer.bind(skeleton)
	layer.source_pose_only = true
	layer.legacy_pistol_frame_weight = 1.0
	layer.legacy_pistol_reference_hips = Quaternion(Vector3.UP, 1.0)
	layer.set_animation_frame_rotation_overrides({"spine":{"x":45.0,"y":45.0,"z":45.0}})
	var before := _snapshot(skeleton)
	layer.apply(0.8, 0.6, 1.0, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0)
	layer.apply_movement_head_level(true, true)
	layer.apply_head_look_at(Vector3(3, 4, 5))
	_expect_unchanged(skeleton, before, "source pose unchanged with all aim/head inputs")
	_expect(layer.get_debug_state().source_pose_only, "source-only mode exposed to diagnostics")
	layer._apply_full_body_peek(&"STANDING", -1.0)
	_expect_unchanged(skeleton, before, "missing authored lean does not synthesize pose")
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	if not _expect(profile is Dictionary and profile.get("authored_peek") is Dictionary, "saved authored-peek profile available"):
		model.queue_free()
		quit(1)
		return
	layer.configure_authored_peek(profile.authored_peek)
	layer._apply_full_body_peek(&"STANDING", -1.0)
	_expect(layer.last_authored_peek_source == "seal_stand2llean", "real source left-lean selected")
	_expect(_has_change(skeleton, before), "real source lean still applies")
	skeleton.reset_bone_poses()
	before = _snapshot(skeleton)
	layer.source_pose_only = false
	layer.legacy_pistol_frame_weight = 0.0
	layer.set_animation_frame_rotation_overrides({})
	layer.apply(0.8, 0.6, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0)
	_expect(_has_change(skeleton, before), "false retains legacy aim path")
	model.queue_free()
	await process_frame
	if failures.is_empty():
		print("SOURCE_POSE_POSTURE_PASS 65-bone invariance, no synthetic lean, real source lean, false fallback")
		quit(0)
	else:
		print("SOURCE_POSE_POSTURE_FAIL checks=", failures.size())
		quit(1)
