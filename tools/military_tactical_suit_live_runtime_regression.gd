extends SceneTree

const EXPECTED_MODEL_NAME := "CanonicalTacticalSuitModel"
const EXPECTED_BONE_COUNT := 71
const EXPECTED_MESH_COUNT := 14
const EXPECTED_VISUAL_SCALE := 1.0

var _frames := 0
var _failed := false


func _init() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	change_scene_to_file("res://main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	if _frames > 30 and _frames < 120:
		return false
	var world := current_scene
	_assert(world != null, "Training Range main scene loads")
	var player := world.get_node_or_null("Player") as CharacterBody3D
	_assert(player != null, "live player exists")
	var collision := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_assert(collision != null and collision.shape is CapsuleShape3D, "gameplay capsule is unchanged")
	var mannequin := player.get_node_or_null("Mannequin")
	_assert(mannequin != null, "player mannequin coordinator exists")
	var driver := mannequin.get_node_or_null("ProductionAnimation")
	_assert(driver != null, "production animation driver exists")
	var model := driver.get("model_root") as Node3D
	_assert(model != null and model.name == EXPECTED_MODEL_NAME, "canonical tactical suit is the live model")
	_assert(
		model.scale.is_equal_approx(Vector3.ONE * EXPECTED_VISUAL_SCALE),
		"live model preserves the canonical meter scale"
	)
	_assert(_materials_are_clear(model), "live suit uses opaque anisotropic materials")
	var skeleton := driver.get("skeleton") as Skeleton3D
	_assert(
		skeleton != null and skeleton.get_bone_count() == EXPECTED_BONE_COUNT,
		"live skeleton has the 47-bone ARP hierarchy plus 24 compatibility fingers"
	)
	_assert(_count_skinned_meshes(model) == EXPECTED_MESH_COUNT, "all 14 suit sections are live and skinned")
	var weapon_attachment := driver.get("weapon_attachment") as BoneAttachment3D
	_assert(weapon_attachment != null and weapon_attachment.bone_name == "mixamorig_RightHand", "weapon remains attached to canonical right hand")
	var weapon := driver.get("weapon_node") as Node3D
	_assert(weapon != null and weapon.find_child("Socket_Muzzle", true, false) != null, "live weapon retains muzzle socket")
	var clips: Dictionary = driver.get("available_clips")
	for clip_name in [&"aim_idle", &"walk_forward", &"run_forward", &"idle_crouch", &"idle_prone"]:
		_assert(clips.has(clip_name), "%s is available in the live animation library" % clip_name)
	var sources: Dictionary = driver.get("source_animation_names")
	for clip_name in [
		&"aim_idle", &"combat_fire", &"idle_crouch", &"prone_forward",
		&"reload", &"jump_forward_action",
	]:
		_assert(
			String(sources.get(clip_name, "")).begins_with("native:"),
			"%s is driven by the native Auto-Rig Pro library" % clip_name
		)
	_assert(
		String(sources.get(&"run_forward_left", ""))
		== "leg_mirrored:run_forward_right"
		and String(sources.get(&"run_forward_right", "")).begins_with("native:"),
		"forward-left keeps the deterministic gameplay mirror of a native ARP take"
	)
	_assert(
		String(sources.get(&"jump_loop", "")) == "native:native__jump",
		"Godot's imported jump-loop alias remains connected to gameplay"
	)
	var posture_name := &"STANDING" if _frames == 30 else &"PRONE"
	var floor_metrics := _floor_metrics(player, skeleton, posture_name)
	if posture_name == &"STANDING":
		_assert(
			float(floor_metrics.get("Hips", -INF)) >= 0.85,
			"meter-scale standing hips retain their imported rest height"
		)
		_assert(
			minf(
				float(floor_metrics.get("LeftToeBase", -INF)),
				float(floor_metrics.get("RightToeBase", -INF))
			) >= 0.03,
			"standing boots remain above the authoritative floor"
		)
	else:
		_assert(
			float(floor_metrics.get("Hips", -INF)) >= 0.05,
			"prone pelvis remains above the authoritative floor"
		)
		_assert(
			minf(
				float(floor_metrics.get("LeftToeBase", -INF)),
				float(floor_metrics.get("RightToeBase", -INF))
			) >= 0.02,
			"prone boots remain above the authoritative floor"
		)
	if _frames == 30:
		player.set("local_input_enabled", false)
		player.velocity = Vector3.ZERO
		_assert(bool(player.call("_try_set_posture", 2)), "live player enters prone through the posture contract")
		return false
	if _failed:
		print("MILITARY_TACTICAL_SUIT_LIVE_RUNTIME_FAIL")
		quit(1)
	else:
		print("MILITARY_TACTICAL_SUIT_LIVE_RUNTIME_PASS")
		quit(0)
	return true


func _floor_metrics(player: CharacterBody3D, skeleton: Skeleton3D, posture: StringName) -> Dictionary:
	var metrics: Dictionary = {}
	var values: Array[String] = []
	for bone_name in [
		"mixamorig_Hips",
		"mixamorig_Head",
		"mixamorig_LeftLeg",
		"mixamorig_RightLeg",
		"mixamorig_LeftFoot",
		"mixamorig_RightFoot",
		"mixamorig_LeftToeBase",
		"mixamorig_RightToeBase",
	]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var point := skeleton.to_global(skeleton.get_bone_global_pose(bone_index).origin)
		var label: String = bone_name.trim_prefix("mixamorig_")
		var floor_height := point.y - player.global_position.y
		metrics[label] = floor_height
		values.append("%s=%.4f" % [label, floor_height])
	print("TACTICAL_SUIT_FLOOR_METRIC posture=%s %s" % [posture, " ".join(values)])
	return metrics


func _count_skinned_meshes(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.skin != null and not mesh_instance.skeleton.is_empty():
			count += 1
	for child in root.get_children():
		count += _count_skinned_meshes(child)
	return count


func _materials_are_clear(root_node: Node) -> bool:
	var found := false
	var pending: Array[Node] = [root_node]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		if (
			mesh_instance.mesh == null
			or mesh_instance.skin == null
			or mesh_instance.skeleton.is_empty()
		):
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			if material == null:
				continue
			found = true
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				print("TACTICAL_SUIT_MATERIAL_FAIL node=%s surface=%d transparency=%s" % [mesh_instance.name, surface_index, material.transparency])
				return false
			if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
				print("TACTICAL_SUIT_MATERIAL_FAIL node=%s surface=%d filter=%s" % [mesh_instance.name, surface_index, material.texture_filter])
				return false
	return found


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	_failed = true
	push_error("FAIL: %s" % message)
