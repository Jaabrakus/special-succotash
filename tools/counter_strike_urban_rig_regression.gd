extends SceneTree

const UrbanScene := preload(
	"res://counter-strike-urban/source/Counter Strike Urban.fbx"
)
const Ps1Scene := preload(
	"res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
)
const RetargetService := preload(
	"res://scripts/labs/animation_retarget_service.gd"
)
const RootSanitizer := preload(
	"res://scripts/player/operator_animation_root_sanitizer.gd"
)

const CLIP_PATH := (
	"res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx"
)
const REPRESENTATIVE_CLIPS := {
	&"urban_idle": "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx",
	&"urban_run": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run forward.fbx",
	&"urban_crouch": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
	&"urban_prone": "res://assets/animations/mixamo/Prone Forward.fbx",
	&"urban_jump": "res://assets/animations/mixamo/Shooter Pack/jump forward.fbx",
	&"urban_reload": "res://assets/animations/mixamo/Reloading.fbx",
}
const BONE_MAP := {
	"mixamorig_Hips": "Bip01 Pelvis",
	"mixamorig_Spine": "Bip01 Spine",
	"mixamorig_Spine1": "Bip01 Spine1",
	"mixamorig_Spine2": "Bip01 Spine3",
	"mixamorig_Neck": "Bip01 Neck",
	"mixamorig_Head": "Bip01 Head",
	"mixamorig_LeftShoulder": "Bip01 L Clavicle",
	"mixamorig_LeftArm": "Bip01 L UpperArm",
	"mixamorig_LeftForeArm": "Bip01 L Forearm",
	"mixamorig_LeftHand": "Bip01 L Hand",
	"mixamorig_RightShoulder": "Bip01 R Clavicle",
	"mixamorig_RightArm": "Bip01 R UpperArm",
	"mixamorig_RightForeArm": "Bip01 R Forearm",
	"mixamorig_RightHand": "Bip01 R Hand",
	"mixamorig_LeftUpLeg": "Bip01 L Thigh",
	"mixamorig_LeftLeg": "Bip01 L Calf",
	"mixamorig_LeftFoot": "Bip01 L Foot",
	"mixamorig_LeftToeBase": "Bip01 L Toe0",
	"mixamorig_RightUpLeg": "Bip01 R Thigh",
	"mixamorig_RightLeg": "Bip01 R Calf",
	"mixamorig_RightFoot": "Bip01 R Foot",
	"mixamorig_RightToeBase": "Bip01 R Toe0",
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var model := UrbanScene.instantiate() as Node3D
	model.scale = Vector3.ONE * 0.94
	model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	root.add_child(model)
	var skeleton := _find_skeleton(model)
	_expect(skeleton != null, "Urban imports a Skeleton3D")
	if skeleton == null:
		_finish()
		return
	for target_name in BONE_MAP.values():
		_expect(
			skeleton.find_bone(String(target_name)) >= 0,
			"mapped Urban bone exists: %s" % String(target_name)
		)

	var player := AnimationPlayer.new()
	player.name = "RegressionAnimationPlayer"
	skeleton.add_child(player)
	player.root_node = player.get_path_to(skeleton)
	var library := AnimationLibrary.new()
	player.add_animation_library("dyn", library)
	var loaded: bool = RetargetService.new().load_fbx(
		{
			"key": &"urban_rifle_idle",
			"path": CLIP_PATH,
		},
		library,
		player,
		skeleton,
		true,
		BONE_MAP,
		true,
		RootSanitizer,
		true
	)
	_expect(loaded, "rest-aware rifle clip is built for Urban")
	var animation := library.get_animation(&"urban_rifle_idle")
	_expect(animation != null, "Urban receives a playable animation")
	if animation != null:
		_expect(animation.get_track_count() >= 20, "core body tracks survive retargeting")
		_expect(
			_has_track(animation, "Bip01 R Hand", Animation.TYPE_ROTATION_3D),
			"right-hand motion drives the Urban weapon hand"
		)
		_expect(
			_has_track(animation, "Bip01 Pelvis", Animation.TYPE_POSITION_3D),
			"root posture is converted to the Urban axis"
		)
		_expect(_keys_are_finite(animation), "all baked transforms are finite")
		player.play(&"dyn/urban_rifle_idle")
		player.seek(animation.length * 0.5, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		_expect(_arm_lengths_are_sane(skeleton), "arms retain human segment lengths")
		var extent := _mapped_world_extent(skeleton)
		_expect(extent.x < 3.0 and extent.y < 3.0 and extent.z < 3.0, "animated body stays inside a human-sized volume")
		var ps1_height := _sample_ps1_height()
		print("URBAN_RIG comparison_height urban=%.4f ps1=%.4f" % [extent.y, ps1_height])
		_expect(ps1_height > 0.0, "PS1 comparison pose can be sampled")
		_expect(
			absf(extent.y - ps1_height) <= ps1_height * 0.05,
			"Urban visible height matches PS1 within five percent"
		)
		_audit_representative_clips(player, library, skeleton)
		_audit_live_animation_map(player, library, skeleton)
	_finish()


func _audit_representative_clips(
	player: AnimationPlayer,
	library: AnimationLibrary,
	skeleton: Skeleton3D
) -> void:
	for clip_key: StringName in REPRESENTATIVE_CLIPS:
		var loaded: bool = RetargetService.new().load_fbx(
			{"key": clip_key, "path": REPRESENTATIVE_CLIPS[clip_key]},
			library,
			player,
			skeleton,
			true,
			BONE_MAP,
			clip_key not in [&"urban_jump", &"urban_reload"],
			RootSanitizer,
			true
		)
		_expect(loaded, "%s retargets onto Urban" % clip_key)
		var animation := library.get_animation(clip_key)
		if animation == null:
			continue
		_expect(_keys_are_finite(animation), "%s has finite transforms" % clip_key)
		_expect(
			_maximum_urban_planar_root(animation, skeleton) < 0.0001,
			"%s cannot move the preview body through the stage" % clip_key
		)
		player.play(StringName("dyn/%s" % clip_key))
		player.seek(animation.length * 0.5, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		_expect(_arm_lengths_are_sane(skeleton), "%s keeps human arm lengths" % clip_key)
		var extent := _mapped_world_extent(skeleton)
		_expect(
			extent.x < 3.0 and extent.y < 3.0 and extent.z < 3.0,
			"%s stays inside a human-sized volume" % clip_key
		)


func _maximum_urban_planar_root(
	animation: Animation,
	skeleton: Skeleton3D
) -> float:
	var maximum := 0.0
	var hips_index := skeleton.find_bone("Bip01 Pelvis")
	var head_index := skeleton.find_bone("Bip01 Head")
	var up_axis := (
		skeleton.get_bone_global_rest(head_index).origin
		- skeleton.get_bone_global_rest(hips_index).origin
	).normalized()
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not str(animation.track_get_path(track_index)).ends_with(":Bip01 Pelvis"):
			continue
		for key_index in range(animation.track_get_key_count(track_index)):
			var position: Vector3 = animation.track_get_key_value(track_index, key_index)
			var horizontal := position - up_axis * up_axis.dot(position)
			maximum = maxf(maximum, horizontal.length())
	return maximum


func _audit_live_animation_map(
	player: AnimationPlayer,
	library: AnimationLibrary,
	skeleton: Skeleton3D
) -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://config/operator_animation_map.json")
	)
	if not parsed is Dictionary or not (parsed as Dictionary).get("clips", {}) is Dictionary:
		_expect(false, "live animation map can be read")
		return
	var unique_paths: Dictionary = {}
	for raw_path: Variant in ((parsed as Dictionary)["clips"] as Dictionary).values():
		unique_paths[String(raw_path)] = true
	var load_failures: Array[String] = []
	var transform_failures: Array[String] = []
	var volume_failures: Array[String] = []
	var path_index := 0
	for resource_path: String in unique_paths:
		var clip_key := StringName("urban_live_%03d" % path_index)
		path_index += 1
		var loaded: bool = RetargetService.new().load_fbx(
			{"key": clip_key, "path": resource_path},
			library,
			player,
			skeleton,
			true,
			BONE_MAP,
			false,
			RootSanitizer,
			true
		)
		if not loaded:
			load_failures.append(resource_path)
			continue
		var animation := library.get_animation(clip_key)
		if (
			animation == null
			or not _keys_are_finite(animation)
			or _maximum_urban_planar_root(animation, skeleton) >= 0.0001
		):
			transform_failures.append(resource_path)
			continue
		player.play(StringName("dyn/%s" % clip_key))
		player.seek(animation.length * 0.5, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var extent := _mapped_world_extent(skeleton)
		if (
			not _arm_lengths_are_sane(skeleton)
			or extent.x >= 3.0
			or extent.y >= 3.0
			or extent.z >= 3.0
		):
			volume_failures.append(resource_path)
	_expect(
		load_failures.is_empty(),
		"all %d gameplay-mapped clips load for Urban%s" % [
			unique_paths.size(),
			"; missing: %s" % load_failures if not load_failures.is_empty() else "",
		]
	)
	_expect(
		transform_failures.is_empty(),
		"all gameplay-mapped Urban clips keep finite in-place transforms%s" % (
			"; invalid: %s" % transform_failures if not transform_failures.is_empty() else ""
		)
	)
	_expect(
		volume_failures.is_empty(),
		"all gameplay-mapped Urban clips keep human limb lengths and bounds%s" % (
			"; invalid: %s" % volume_failures if not volume_failures.is_empty() else ""
		)
	)


func _sample_ps1_height() -> float:
	var model := Ps1Scene.instantiate() as Node3D
	model.scale = Vector3.ONE * 55.0
	model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	root.add_child(model)
	var target_skeleton := _find_skeleton(model)
	if target_skeleton == null:
		return 0.0
	var player := AnimationPlayer.new()
	target_skeleton.add_child(player)
	player.root_node = player.get_path_to(target_skeleton)
	var library := AnimationLibrary.new()
	player.add_animation_library("dyn", library)
	var loaded: bool = RetargetService.new().load_fbx(
		{"key": &"ps1_rifle_idle", "path": CLIP_PATH},
		library,
		player,
		target_skeleton,
		true,
		{},
		false,
		RootSanitizer,
		true
	)
	if not loaded:
		return 0.0
	var animation := library.get_animation(&"ps1_rifle_idle")
	if animation == null:
		return 0.0
	player.play(&"dyn/ps1_rifle_idle")
	player.seek(animation.length * 0.5, true)
	player.advance(0.0)
	target_skeleton.force_update_all_bone_transforms()
	return _ps1_world_height(target_skeleton)


func _ps1_world_height(target_skeleton: Skeleton3D) -> float:
	var bounds := AABB()
	var initialized := false
	for source_name in BONE_MAP.keys():
		var index := target_skeleton.find_bone(String(source_name))
		if index < 0:
			continue
		var point := target_skeleton.to_global(
			target_skeleton.get_bone_global_pose(index).origin
		)
		if not initialized:
			bounds = AABB(point, Vector3.ZERO)
			initialized = true
		else:
			bounds = bounds.expand(point)
	return bounds.size.y if initialized else 0.0


func _has_track(animation: Animation, bone_name: String, track_type: int) -> bool:
	for track_index in animation.get_track_count():
		if (
			animation.track_get_type(track_index) == track_type
			and str(animation.track_get_path(track_index)).ends_with(":" + bone_name)
		):
			return true
	return false


func _keys_are_finite(animation: Animation) -> bool:
	for track_index in animation.get_track_count():
		for key_index in animation.track_get_key_count(track_index):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if value is Vector3 and not (value as Vector3).is_finite():
				return false
			if value is Quaternion and not (value as Quaternion).is_finite():
				return false
	return true


func _arm_lengths_are_sane(skeleton: Skeleton3D) -> bool:
	for side in ["L", "R"]:
		var upper := skeleton.find_bone("Bip01 %s UpperArm" % side)
		var forearm := skeleton.find_bone("Bip01 %s Forearm" % side)
		var hand := skeleton.find_bone("Bip01 %s Hand" % side)
		var upper_length := skeleton.get_bone_global_pose(upper).origin.distance_to(
			skeleton.get_bone_global_pose(forearm).origin
		)
		var lower_length := skeleton.get_bone_global_pose(forearm).origin.distance_to(
			skeleton.get_bone_global_pose(hand).origin
		)
		if upper_length < 0.001 or lower_length < 0.001:
			return false
		if upper_length > 0.02 or lower_length > 0.02:
			return false
	return true


func _mapped_world_extent(skeleton: Skeleton3D) -> Vector3:
	var bounds := AABB()
	var initialized := false
	for target_name in BONE_MAP.values():
		var index := skeleton.find_bone(String(target_name))
		var point := skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
		if not initialized:
			bounds = AABB(point, Vector3.ZERO)
			initialized = true
		else:
			bounds = bounds.expand(point)
	return bounds.size


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("URBAN_RIG PASS ", message)
		return
	failures.append(message)
	push_error("URBAN_RIG FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("COUNTER_STRIKE_URBAN_RIG_REGRESSION PASS")
		quit(0)
		return
	quit(1)
