class_name SocomOperatorAssetRuntime
extends RefCounted

## Owns model construction, weapon attachment and runtime Mixamo retargeting.
## Keeping asset plumbing out of the driver makes locomotion logic testable.

const TROOPER_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const TROOPER_TEXTURE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const AK47_SCENE := preload("res://assets/weapons/ps1_ak47/source/ak-47.fbx")
const AK47_TEXTURE := preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
const ROOT_SANITIZER := preload("res://scripts/player/operator_animation_root_sanitizer.gd")
const WEAPON_CONTRACT := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WEAPON_LOADOUT_PATH := "res://config/weapons/operator_loadout.json"

var model_root: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var weapon_attachment: BoneAttachment3D
var weapon_node: Node3D
var equipped_weapon_config: Dictionary = {}
var calibrated_weapon_pivot: Node3D
var weapon_sockets: Dictionary = {}
var _base_weapon_pivot_position := Vector3.ZERO
var _base_weapon_pivot_rotation := Vector3.ZERO
var _base_socket_positions: Dictionary = {}
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
	var equipped_config := _load_equipped_weapon_config()
	if not equipped_config.is_empty() and _attach_calibrated_weapon(equipped_config):
		return
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

	# Gameplay-facing sockets live in normalized weapon space. The imported AK
	# mesh has asset-specific transforms, while this parent is deliberately
	# cancelled against the operator scale, so these positions remain metres.
	# The arm solver consumes the same contract for every future weapon skin.
	var trigger_grip := Marker3D.new()
	trigger_grip.name = "Socket_RightHand"
	trigger_grip.position = Vector3.ZERO
	weapon_node.add_child(trigger_grip)

	var support_grip := Marker3D.new()
	support_grip.name = "Socket_LeftHand"
	support_grip.position = Vector3(-0.22, -0.01, -0.08)
	# The placeholder AK has no authored foregrip socket. The solver may refine
	# this marker to its anatomically reachable fallback. Imported weapons set
	# this metadata true after calibration and retain their fixed socket.
	support_grip.set_meta("authored_weapon_socket", false)
	weapon_node.add_child(support_grip)

	var muzzle := Marker3D.new()
	muzzle.name = "Socket_Muzzle"
	muzzle.position = Vector3(0.0, 0.0, -0.70)
	weapon_node.add_child(muzzle)

	var barrel_base := Marker3D.new()
	barrel_base.name = "Socket_BarrelBase"
	barrel_base.position = Vector3(0.0, 0.0, -0.12)
	weapon_node.add_child(barrel_base)

	var ejection := Marker3D.new()
	ejection.name = "Socket_Ejection"
	ejection.position = Vector3(0.05, 0.03, -0.10)
	weapon_node.add_child(ejection)

	var optic := Marker3D.new()
	optic.name = "Socket_Optic"
	optic.position = Vector3(0.0, 0.08, -0.18)
	weapon_node.add_child(optic)

	weapon_node.add_child(pivot)
	weapon_attachment.add_child(weapon_node)


func _load_equipped_weapon_config() -> Dictionary:
	return WEAPON_CONTRACT.load_equipped_config()


func _attach_calibrated_weapon(config: Dictionary) -> bool:
	var model_path := String(config.get("model_fbx", ""))
	var model_scene := load(model_path) as PackedScene
	if model_scene == null:
		push_warning("Saved weapon model could not be loaded: %s" % model_path)
		return false

	equipped_weapon_config = config.duplicate(true)
	weapon_node = Node3D.new()
	weapon_node.name = "Attached_%s" % String(config.get("weapon_id", "Weapon"))
	weapon_node.set_meta("weapon_id", StringName(config.get("weapon_id", "")))
	weapon_node.set_meta("rig_config", String(config.get("_rig_config_path", "")))
	var inverse_scale := 1.0 / operator_scale
	var mount: Dictionary = config.get("operator_mount", {})
	weapon_node.position = _vector3_from_map(
		mount.get("position", {}),
		grip_position
	) * inverse_scale
	weapon_node.rotation_degrees = _vector3_from_map(
		mount.get("rotation_degrees", {}),
		grip_rotation
	)
	weapon_node.scale = Vector3.ONE * inverse_scale

	calibrated_weapon_pivot = Node3D.new()
	var calibrated_pivot := calibrated_weapon_pivot
	calibrated_pivot.name = "CalibratedWeaponPivot"
	var grip: Dictionary = config.get("grip_offset", {})
	calibrated_pivot.position = Vector3(
		float(grip.get("pos_x", 0.0)),
		float(grip.get("pos_y", 0.0)),
		float(grip.get("pos_z", 0.0))
	)
	calibrated_pivot.rotation_degrees = Vector3(
		float(grip.get("rot_x", 0.0)),
		float(grip.get("rot_y", 0.0)),
		float(grip.get("rot_z", 0.0))
	)

	var weapon_model := model_scene.instantiate() as Node3D
	weapon_model.name = "WeaponMesh"
	weapon_model.scale = Vector3.ONE * float(config.get("normalized_scale", 1.0))
	weapon_model.rotation_degrees = _vector3_from_map(
		config.get("model_rotation_degrees", {}),
		_default_model_rotation(model_path)
	)
	if "ps1_ak47" in model_path:
		var ak_material := StandardMaterial3D.new()
		ak_material.albedo_texture = AK47_TEXTURE
		ak_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_apply_material_recursive(weapon_model, ak_material)

	var sockets: Dictionary = config.get("weapon_sockets", {})
	var current_socket_contract := (
		bool(config.get("socket_contract_authored", false))
		and sockets.has("right_hand_grip_target")
		and sockets.has("barrel_base_socket")
	)
	var right_position := _vector3_from_map(
		sockets.get("right_hand_grip_target", {}),
		Vector3.ZERO
	)
	var left_position := _vector3_from_map(
		sockets.get("left_hand_ik_target", {}),
		Vector3(-0.22, -0.01, -0.08)
	)
	var muzzle_position := _vector3_from_map(
		sockets.get("muzzle_socket", {}),
		Vector3(0.70, 0.02, 0.0)
	)
	var barrel_base_position := _vector3_from_map(
		sockets.get("barrel_base_socket", {}),
		_derived_barrel_base(right_position, muzzle_position)
	)
	# Socket coordinates are calibrated in normalized weapon metres, not in the
	# imported mesh's arbitrary FBX scale. Keep them beside the scaled model.
	_add_weapon_socket(calibrated_pivot, "Socket_RightHand", right_position, true)
	_add_weapon_socket(
		calibrated_pivot,
		"Socket_LeftHand",
		left_position,
		current_socket_contract
	)
	_add_weapon_socket(calibrated_pivot, "Socket_BarrelBase", barrel_base_position, true)
	_add_weapon_socket(calibrated_pivot, "Socket_Muzzle", muzzle_position, true)
	_add_weapon_socket(
		calibrated_pivot,
		"Socket_Ejection",
		_vector3_from_map(sockets.get("ejection_port", {}), Vector3.ZERO),
		true
	)
	_add_weapon_socket(
		calibrated_pivot,
		"Socket_Optic",
		_vector3_from_map(sockets.get("optic_rail", {}), Vector3.ZERO),
		true
	)

	calibrated_pivot.add_child(weapon_model)
	weapon_node.add_child(calibrated_pivot)
	weapon_attachment.add_child(weapon_node)
	_cache_weapon_map_baseline()
	return true


func apply_animation_hand_map(resource_path: String, explicit_stance: StringName = &"") -> bool:
	_restore_weapon_map_baseline()
	if resource_path.is_empty() or equipped_weapon_config.is_empty():
		return false
	var raw_map: Variant = {}
	var stances_dict: Variant = equipped_weapon_config.get("stances", {})
	if stances_dict is Dictionary:
		var stance_key := String(explicit_stance).to_upper()
		if stance_key not in ["STANDING", "CROUCHED", "PRONE"] and "prone" in resource_path.to_lower():
			stance_key = "PRONE"
		elif stance_key not in ["STANDING", "CROUCHED", "PRONE"] and "crouch" in resource_path.to_lower():
			stance_key = "CROUCHED"
		elif stance_key not in ["STANDING", "CROUCHED", "PRONE"] and ("stand" in resource_path.to_lower() or "aim_idle" in resource_path.to_lower() or "idle" in resource_path.to_lower()):
			stance_key = "STANDING"
		if not stance_key.is_empty() and (stances_dict as Dictionary).has(stance_key):
			raw_map = (stances_dict as Dictionary)[stance_key]

	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		var raw_maps: Variant = equipped_weapon_config.get("animation_hand_maps", {})
		if raw_maps is Dictionary:
			var maps := raw_maps as Dictionary
			raw_map = maps.get(resource_path, {})
			if not raw_map is Dictionary or (raw_map as Dictionary).is_empty():
				for candidate_path in maps.keys():
					if String(candidate_path).get_file() == resource_path.get_file() or String(candidate_path) == resource_path:
						raw_map = maps[candidate_path]
						break
	if not raw_map is Dictionary or (raw_map as Dictionary).is_empty():
		return false
	var hand_map := raw_map as Dictionary
	# The top-level grip_offset is the single weapon master anchor. Legacy
	# stance and clip maps may contain mount fields, but runtime must ignore them
	# so animation changes cannot teleport or rotate the rifle.
	_apply_mapped_socket(
		"Socket_LeftHand",
		hand_map.get("left_grip", hand_map.get("left_hand_target", {}))
	)
	_apply_mapped_socket(
		"Socket_RightHand",
		hand_map.get("right_grip", hand_map.get("right_hand_target", {}))
	)
	if weapon_node != null:
		weapon_node.set_meta("active_animation_hand_map", resource_path)
		weapon_node.set_meta("support_hand_pose", {
			"palm_pitch_deg": float(hand_map.get("palm_pitch_deg", 0.0)),
			"palm_yaw_deg": float(hand_map.get("palm_yaw_deg", 0.0)),
			"palm_roll_deg": float(hand_map.get("palm_roll_deg", 0.0)),
			"finger_curl": float(hand_map.get("finger_curl", 0.0)),
			"thumb_wrap": float(hand_map.get("thumb_wrap", 0.0)),
		})
	return true


func _cache_weapon_map_baseline() -> void:
	weapon_sockets.clear()
	_base_socket_positions.clear()
	if calibrated_weapon_pivot == null:
		return
	_base_weapon_pivot_position = calibrated_weapon_pivot.position
	_base_weapon_pivot_rotation = calibrated_weapon_pivot.rotation_degrees
	for socket_name in [
		"Socket_RightHand", "Socket_LeftHand", "Socket_BarrelBase",
		"Socket_Muzzle", "Socket_Ejection", "Socket_Optic",
	]:
		var socket := calibrated_weapon_pivot.find_child(socket_name, true, false) as Marker3D
		if socket != null:
			weapon_sockets[socket_name] = socket
			_base_socket_positions[socket_name] = socket.position


func _restore_weapon_map_baseline() -> void:
	if calibrated_weapon_pivot != null:
		calibrated_weapon_pivot.position = _base_weapon_pivot_position
		calibrated_weapon_pivot.rotation_degrees = _base_weapon_pivot_rotation
	for socket_name in weapon_sockets.keys():
		var socket := weapon_sockets[socket_name] as Marker3D
		if socket != null and _base_socket_positions.has(socket_name):
			socket.position = _base_socket_positions[socket_name]
	if weapon_node != null:
		weapon_node.remove_meta("active_animation_hand_map")
		weapon_node.set_meta(
			"support_hand_pose",
			equipped_weapon_config.get("support_hand_pose", {})
		)


func _apply_mapped_socket(socket_name: String, value: Variant) -> void:
	var socket := weapon_sockets.get(socket_name) as Marker3D
	if socket != null:
		socket.position = _vector3_from_map(value, socket.position)


func _default_model_rotation(model_path: String) -> Vector3:
	if "ps1_ak47" in model_path:
		return Vector3(0.0, 180.0, 0.0)
	return Vector3(0.0, -90.0, 0.0)


func _add_weapon_socket(
	parent: Node3D,
	socket_name: String,
	local_position: Vector3,
	authored: bool
) -> Marker3D:
	var socket := Marker3D.new()
	socket.name = socket_name
	socket.position = local_position
	socket.set_meta("authored_weapon_socket", authored)
	parent.add_child(socket)
	return socket


func _derived_barrel_base(right_grip: Vector3, muzzle: Vector3) -> Vector3:
	var barrel_axis := (muzzle - right_grip).normalized()
	if barrel_axis.length_squared() < 0.99:
		barrel_axis = Vector3.RIGHT
	return muzzle - barrel_axis * minf(0.18, maxf(muzzle.distance_to(right_grip) * 0.35, 0.08))


func _vector3_from_map(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Dictionary:
		return fallback
	var map := value as Dictionary
	return Vector3(
		float(map.get("x", fallback.x)),
		float(map.get("y", fallback.y)),
		float(map.get("z", fallback.z))
	)


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
