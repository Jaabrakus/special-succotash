class_name SocomOperatorAssetRuntime
extends RefCounted

## Owns model construction, weapon attachment and runtime Mixamo retargeting.
## Keeping asset plumbing out of the driver makes locomotion logic testable.

const TROOPER_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const TROOPER_TEXTURE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const AK47_SCENE := preload("res://assets/weapons/ps1_ak47/source/ak-47.fbx")
const AK47_TEXTURE := preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
const ROOT_SANITIZER := preload("res://scripts/player/operator_animation_root_sanitizer.gd")

var model_root: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var weapon_attachment: BoneAttachment3D
var weapon_node: Node3D
var animation_library: AnimationLibrary
var available_clips: Dictionary = {}
var source_animation_names: Dictionary = {}
var profile
var operator_scale: float = 62.0
var grip_position := Vector3(-0.02, 0.08, 0.05)
var grip_rotation := Vector3(-90.0, 180.0, 0.0)


func build(
	owner: Node3D,
	animation_profile,
	scale_value: float,
	grip_pos: Vector3,
	grip_rot: Vector3
) -> Dictionary:
	profile = animation_profile
	operator_scale = scale_value
	grip_position = grip_pos
	grip_rotation = grip_rot
	model_root = TROOPER_SCENE.instantiate() as Node3D
	model_root.name = "TrooperModel"
	model_root.scale = Vector3.ONE * operator_scale
	model_root.rotation.y = PI
	owner.add_child(model_root)
	_apply_texture(model_root)
	skeleton = _find_skeleton(model_root)
	if skeleton == null:
		push_error("Trooper rig has no Skeleton3D")
		return get_runtime()
	_ensure_65_bone_contract()
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	skeleton.add_child(animation_player)
	animation_player.owner = model_root
	animation_player.root_node = animation_player.get_path_to(skeleton)
	_attach_weapon()
	_build_animation_library()
	return get_runtime()


func get_runtime() -> Dictionary:
	return {
		"model_root": model_root,
		"animation_player": animation_player,
		"skeleton": skeleton,
		"weapon_attachment": weapon_attachment,
		"weapon_node": weapon_node,
		"animation_library": animation_library,
		"available_clips": available_clips,
		"source_animation_names": source_animation_names,
	}


func set_operator_scale(new_scale: float) -> void:
	operator_scale = new_scale
	if model_root != null:
		model_root.scale = Vector3.ONE * operator_scale
	if weapon_node != null:
		var inverse_scale := 1.0 / operator_scale
		weapon_node.position = grip_position * inverse_scale
		weapon_node.scale = Vector3.ONE * inverse_scale


func get_source_animation_name(clip_name: StringName) -> StringName:
	return StringName(source_animation_names.get(clip_name, &""))


func _ensure_65_bone_contract() -> void:
	for side in ["Left", "Right"]:
		var hand_index := skeleton.find_bone("mixamorig_%sHand" % side)
		if hand_index < 0:
			continue
		for finger in ["Middle", "Ring", "Pinky"]:
			var parent_index := hand_index
			for segment in range(1, 5):
				var bone_name := "mixamorig_%sHand%s%d" % [side, finger, segment]
				var bone_index := skeleton.find_bone(bone_name)
				if bone_index < 0:
					bone_index = skeleton.add_bone(bone_name)
					var reference := skeleton.find_bone("mixamorig_%sHandIndex%d" % [side, segment])
					if reference >= 0:
						skeleton.set_bone_rest(bone_index, skeleton.get_bone_rest(reference))
				skeleton.set_bone_parent(bone_index, parent_index)
				parent_index = bone_index


func _apply_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_texture = TROOPER_TEXTURE
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 0.95
		node.material_override = material
	for child in node.get_children():
		_apply_texture(child)


func _attach_weapon() -> void:
	if skeleton.find_bone("mixamorig_RightHand") < 0:
		return
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "AK47_Attachment"
	weapon_attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(weapon_attachment)
	weapon_node = Node3D.new()
	weapon_node.name = "AttachedAK47"
	var inverse_scale := 1.0 / operator_scale
	weapon_node.position = grip_position * inverse_scale
	weapon_node.rotation_degrees = grip_rotation
	weapon_node.scale = Vector3.ONE * inverse_scale
	var pivot := Node3D.new()
	pivot.name = "AK47_Pivot"
	var weapon_model := AK47_SCENE.instantiate() as Node3D
	weapon_model.name = "WeaponMesh"
	weapon_model.scale = Vector3.ONE * 0.030
	weapon_model.position = Vector3(0.0, 0.02, -0.05)
	weapon_model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = AK47_TEXTURE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_apply_material_recursive(weapon_model, material)
	pivot.add_child(weapon_model)

	# Gameplay-facing sockets live on the calibrated weapon mesh. They are kept
	# independent of the operator skin so swapping a character cannot break fire.
	var muzzle := Marker3D.new()
	muzzle.name = "Socket_Muzzle"
	muzzle.position = Vector3(0.70, 0.02, 0.0)
	weapon_model.add_child(muzzle)

	var ejection := Marker3D.new()
	ejection.name = "Socket_Ejection"
	ejection.position = Vector3(0.05, 0.03, 0.06)
	weapon_model.add_child(ejection)

	weapon_node.add_child(pivot)
	weapon_attachment.add_child(weapon_node)


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_apply_material_recursive(child, material)


func _build_animation_library() -> void:
	animation_library = AnimationLibrary.new()
	available_clips.clear()
	source_animation_names.clear()
	for raw_clip_name in profile.clip_paths.keys():
		var clip_name := StringName(raw_clip_name)
		var clip_path := String(profile.clip_paths[clip_name])
		var resource := load(clip_path)
		if resource is Animation:
			var authored := (resource as Animation).duplicate() as Animation
			ROOT_SANITIZER.sanitize(authored, profile.is_looping(clip_name))
			authored.loop_mode = Animation.LOOP_LINEAR if profile.is_looping(clip_name) else Animation.LOOP_NONE
			animation_library.add_animation(clip_name, authored)
			available_clips[clip_name] = true
			source_animation_names[clip_name] = StringName("authored:%s" % clip_path.get_file())
			continue
		var packed := resource as PackedScene
		if packed == null:
			continue
		var temporary := packed.instantiate()
		var source_player := _find_animation_player(temporary)
		if source_player != null and not source_player.get_animation_list().is_empty():
			var source_name := _select_source_animation_name(source_player)
			if source_name != &"":
				var retargeted := _retarget_animation(source_player.get_animation(source_name))
				ROOT_SANITIZER.sanitize(retargeted, profile.is_looping(clip_name))
				retargeted.loop_mode = Animation.LOOP_LINEAR if profile.is_looping(clip_name) else Animation.LOOP_NONE
				animation_library.add_animation(clip_name, retargeted)
				available_clips[clip_name] = true
				source_animation_names[clip_name] = source_name
		temporary.queue_free()
	_apply_mirrored_clips()
	_apply_leg_mirrored_clips()
	_apply_clip_aliases()
	_apply_clip_pose_yaw_offsets()
	animation_player.add_animation_library("", animation_library)


func _apply_mirrored_clips() -> void:
	for raw_target in profile.mirrored_clips.keys():
		var target := StringName(raw_target)
		var source: StringName = profile.mirror_source(target)
		if source == &"" or not animation_library.has_animation(source):
			continue
		var mirrored := _mirror_animation(animation_library.get_animation(source))
		mirrored.loop_mode = Animation.LOOP_LINEAR if profile.is_looping(target) else Animation.LOOP_NONE
		if animation_library.has_animation(target):
			animation_library.remove_animation(target)
		animation_library.add_animation(target, mirrored)
		available_clips[target] = true
		source_animation_names[target] = StringName("mirrored:%s" % source)


func _mirror_animation(source: Animation) -> Animation:
	var mirrored := source.duplicate() as Animation
	var reflection := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	for track in range(mirrored.get_track_count()):
		mirrored.track_set_path(track, NodePath(_swap_left_right(str(mirrored.track_get_path(track)))))
		var track_type := mirrored.track_get_type(track)
		for key in range(mirrored.track_get_key_count(track)):
			if track_type == Animation.TYPE_POSITION_3D:
				var position: Vector3 = mirrored.track_get_key_value(track, key)
				position.x = -position.x
				mirrored.track_set_key_value(track, key, position)
			elif track_type == Animation.TYPE_ROTATION_3D:
				var rotation: Quaternion = mirrored.track_get_key_value(track, key)
				var mirrored_basis := reflection * Basis(rotation) * reflection
				mirrored.track_set_key_value(
					track,
					key,
					mirrored_basis.get_rotation_quaternion().normalized()
				)
	return mirrored


func _apply_leg_mirrored_clips() -> void:
	for raw_target in profile.leg_mirrored_clips.keys():
		var target := StringName(raw_target)
		var source: StringName = profile.leg_mirror_source(target)
		if source == &"" or not animation_library.has_animation(source):
			continue
		var mirrored := _mirror_leg_tracks(animation_library.get_animation(source))
		mirrored.loop_mode = Animation.LOOP_LINEAR if profile.is_looping(target) else Animation.LOOP_NONE
		if animation_library.has_animation(target):
			animation_library.remove_animation(target)
		animation_library.add_animation(target, mirrored)
		available_clips[target] = true
		source_animation_names[target] = StringName("leg_mirrored:%s" % source)


func _apply_clip_aliases() -> void:
	for raw_target in profile.clip_aliases.keys():
		var target := StringName(raw_target)
		var source: StringName = profile.alias_source(target)
		if source == &"" or not animation_library.has_animation(source):
			continue
		var aliased := animation_library.get_animation(source).duplicate() as Animation
		aliased.loop_mode = Animation.LOOP_LINEAR if profile.is_looping(target) else Animation.LOOP_NONE
		if animation_library.has_animation(target):
			animation_library.remove_animation(target)
		animation_library.add_animation(target, aliased)
		available_clips[target] = true
		source_animation_names[target] = StringName("alias:%s" % source)


func _apply_clip_pose_yaw_offsets() -> void:
	for raw_clip_name in profile.pose_yaw_offsets_degrees.keys():
		var clip_name := StringName(raw_clip_name)
		var yaw_degrees: float = profile.pose_yaw_offset_degrees(clip_name)
		if is_zero_approx(yaw_degrees) or not animation_library.has_animation(clip_name):
			continue
		var animation := animation_library.get_animation(clip_name)
		var yaw_offset := Quaternion(Vector3.UP, deg_to_rad(yaw_degrees))
		for track in range(animation.get_track_count()):
			if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			if not str(animation.track_get_path(track)).ends_with(":mixamorig_Hips"):
				continue
			for key in range(animation.track_get_key_count(track)):
				var rotation: Quaternion = animation.track_get_key_value(track, key)
				animation.track_set_key_value(
					track,
					key,
					(yaw_offset * rotation).normalized()
				)


func _mirror_leg_tracks(source: Animation) -> Animation:
	var mirrored := source.duplicate() as Animation
	var reflection := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	for track in range(mirrored.get_track_count()):
		var path := str(mirrored.track_get_path(track))
		if not _is_leg_track(path):
			continue
		mirrored.track_set_path(track, NodePath(_swap_left_right(path)))
		var track_type := mirrored.track_get_type(track)
		for key in range(mirrored.track_get_key_count(track)):
			if track_type == Animation.TYPE_POSITION_3D:
				var position: Vector3 = mirrored.track_get_key_value(track, key)
				position.x = -position.x
				mirrored.track_set_key_value(track, key, position)
			elif track_type == Animation.TYPE_ROTATION_3D:
				var rotation: Quaternion = mirrored.track_get_key_value(track, key)
				var mirrored_basis := reflection * Basis(rotation) * reflection
				mirrored.track_set_key_value(
					track,
					key,
					mirrored_basis.get_rotation_quaternion().normalized()
				)
	return mirrored


func _is_leg_track(path: String) -> bool:
	for token in [
		"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End",
		"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End",
	]:
		if token in path:
			return true
	return false


func _swap_left_right(path: String) -> String:
	return path.replace("Left", "__MIRROR_SIDE__").replace("Right", "Left").replace("__MIRROR_SIDE__", "Right")


func _retarget_animation(source: Animation) -> Animation:
	var retargeted := source.duplicate() as Animation
	var root_node := animation_player.get_node(animation_player.root_node)
	var skeleton_path := root_node.get_path_to(skeleton)
	for track in range(retargeted.get_track_count() - 1, -1, -1):
		var source_path := str(retargeted.track_get_path(track))
		var raw_bone := source_path.split(":")[-1]
		var normalized := raw_bone.replace("mixamorig:", "mixamorig_")
		if not normalized.begins_with("mixamorig_"):
			normalized = "mixamorig_" + normalized
		var target_bone := raw_bone if skeleton.find_bone(raw_bone) >= 0 else normalized
		if skeleton.find_bone(target_bone) < 0:
			retargeted.remove_track(track)
			continue
		retargeted.track_set_path(track, NodePath(str(skeleton_path) + ":" + target_bone))
		if ("Hips" in raw_bone or "root" in raw_bone.to_lower()) and retargeted.track_get_type(track) == Animation.TYPE_POSITION_3D:
			for key in range(retargeted.track_get_key_count(track)):
				var position: Vector3 = retargeted.track_get_key_value(track, key)
				position.x = 0.0
				position.z = 0.0
				position.y *= 0.0191988
				retargeted.track_set_key_value(track, key, position)
	return retargeted


func _select_source_animation_name(player: AnimationPlayer) -> StringName:
	var names := player.get_animation_list()
	if names.has(&"mixamo_com"):
		return &"mixamo_com"
	for animation_name in names:
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
