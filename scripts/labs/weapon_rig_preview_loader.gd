class_name SocomWeaponRigPreview
extends RefCounted

## Shared reader for the weapon contract authored by the Gunsmith. The
## Animation Studio is deliberately a consumer: it never invents a second set
## of grip, muzzle, or model offsets.

const WEAPON_LOADOUT_PATH := "res://config/weapons/operator_loadout.json"
const AK47_TEXTURE := preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
const WEAPON_CONTRACT := preload("res://scripts/weapons/weapon_rig_contract.gd")


static func resolve_config_path(fallback_weapon_id: String) -> String:
	return WEAPON_CONTRACT.resolve_config_path(fallback_weapon_id)


static func load_config(config_path: String) -> Dictionary:
	return WEAPON_CONTRACT.load_config(config_path)


static func attach_to_hand(
	config: Dictionary,
	attachment: BoneAttachment3D,
	fallback_mount_position: Vector3,
	fallback_mount_rotation: Vector3,
	operator_inverse_scale: float = 1.0
) -> Dictionary:
	var model_path := String(config.get("model_fbx", ""))
	var model_scene := load(model_path) as PackedScene
	if model_scene == null or attachment == null:
		return {}

	var weapon_root := Node3D.new()
	weapon_root.name = "Attached_%s" % String(config.get("weapon_id", "Weapon"))
	weapon_root.set_meta("weapon_id", StringName(config.get("weapon_id", "")))
	weapon_root.set_meta("rig_config", String(config.get("_rig_config_path", "")))
	var mount: Dictionary = config.get("operator_mount", {})
	weapon_root.position = vector3_from_map(
		mount.get("position", {}), fallback_mount_position
	) * operator_inverse_scale
	weapon_root.rotation_degrees = vector3_from_map(
		mount.get("rotation_degrees", {}), fallback_mount_rotation
	)
	weapon_root.scale = Vector3.ONE * operator_inverse_scale

	var calibrated_pivot := Node3D.new()
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
	calibrated_pivot.set_meta("canonical_weapon_pivot_transform", calibrated_pivot.transform)

	var weapon_model := model_scene.instantiate() as Node3D
	weapon_model.name = "WeaponMesh"
	var model_scale := float(config.get("normalized_scale", 1.0))
	var legacy_contract := int(config.get("schema_version", 0)) < 3
	if legacy_contract and "ps1_ak47" in model_path and is_equal_approx(model_scale, 1.0):
		model_scale = 0.030
		weapon_model.position = Vector3(0.0, 0.02, -0.05)
	weapon_model.scale = Vector3.ONE * model_scale
	weapon_model.rotation_degrees = vector3_from_map(
		config.get("model_rotation_degrees", {}), _default_model_rotation(model_path)
	)
	if "ps1_ak47" in model_path:
		var material := StandardMaterial3D.new()
		material.albedo_texture = AK47_TEXTURE
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_apply_material(weapon_model, material)

	var sockets: Dictionary = config.get("weapon_sockets", {})
	var right_position := vector3_from_map(
		sockets.get("right_hand_grip_target", {}), Vector3.ZERO
	)
	var left_position := vector3_from_map(
		sockets.get("left_hand_ik_target", {}), Vector3(-0.22, -0.01, -0.08)
	)
	var muzzle_position := vector3_from_map(
		sockets.get("muzzle_socket", {}), Vector3(0.70, 0.02, 0.0)
	)
	var barrel_position := vector3_from_map(
		sockets.get("barrel_base_socket", {}),
		_derived_barrel_base(right_position, muzzle_position)
	)
	var result := {
		"weapon_root": weapon_root,
		"calibrated_pivot": calibrated_pivot,
		"right_hand": _socket(calibrated_pivot, "Socket_RightHand", right_position),
		"left_hand": _socket(calibrated_pivot, "Socket_LeftHand", left_position),
		"barrel_base": _socket(calibrated_pivot, "Socket_BarrelBase", barrel_position),
		"muzzle": _socket(calibrated_pivot, "Socket_Muzzle", muzzle_position),
		"ejection": _socket(
			calibrated_pivot,
			"Socket_Ejection",
			vector3_from_map(sockets.get("ejection_port", {}), Vector3.ZERO)
		),
		"optic": _socket(
			calibrated_pivot,
			"Socket_Optic",
			vector3_from_map(sockets.get("optic_rail", {}), Vector3.ZERO)
		),
		"config": config,
	}
	calibrated_pivot.add_child(weapon_model)
	weapon_root.add_child(calibrated_pivot)
	attachment.add_child(weapon_root)
	return result


static func apply_animation_hand_map(
	config: Dictionary,
	resource_path: String,
	calibrated_pivot: Node3D,
	left_hand: Marker3D,
	right_hand: Marker3D,
	explicit_posture: StringName = &"",
	candidate_keys: PackedStringArray = PackedStringArray()
) -> bool:
	_restore_preview_socket_baseline(calibrated_pivot, left_hand, right_hand)
	var raw_map: Variant = {}
	# Match gameplay: a clip-specific hand map is more precise than a broad
	# stance fallback. The old reverse order connected action clips to idle
	# grips and folded both elbows through one another.
	var raw_maps: Variant = config.get("animation_hand_maps", {})
	if raw_maps is Dictionary:
		var maps := raw_maps as Dictionary
		var lookup_keys := PackedStringArray([resource_path])
		lookup_keys.append_array(candidate_keys)
		for lookup_key in lookup_keys:
			raw_map = maps.get(String(lookup_key), {})
			if raw_map is Dictionary and not (raw_map as Dictionary).is_empty():
				break
		if not raw_map is Dictionary or (raw_map as Dictionary).is_empty():
			for candidate_path in maps.keys():
				if _hand_map_key_matches(String(candidate_path), lookup_keys):
					raw_map = maps[candidate_path]
					break
	if not raw_map is Dictionary or (raw_map as Dictionary).is_empty():
		var stances_dict: Variant = config.get("stances", {})
		if stances_dict is Dictionary:
			var stance_key := String(explicit_posture).to_upper()
			var semantic_text := (resource_path + " " + " ".join(candidate_keys)).to_lower()
			if stance_key not in ["STANDING", "CROUCHED", "PRONE"] and "prone" in semantic_text:
				stance_key = "PRONE"
			elif stance_key not in ["STANDING", "CROUCHED", "PRONE"] and ("crouch" in semantic_text or "kneel" in semantic_text):
				stance_key = "CROUCHED"
			elif stance_key not in ["STANDING", "CROUCHED", "PRONE"]:
				stance_key = "STANDING"
			if not stance_key.is_empty() and (stances_dict as Dictionary).has(stance_key):
				raw_map = (stances_dict as Dictionary)[stance_key]
	if not raw_map is Dictionary or (raw_map as Dictionary).is_empty():
		return false
	var hand_map := raw_map as Dictionary
	if calibrated_pivot:
		# The Studio IK pass needs the same palm orientation that Gunsmith used
		# when this grip was authored. Keep the resolved map on the preview pivot
		# so the hand and elbow solver cannot silently fall back to a bare weapon
		# socket basis.
		calibrated_pivot.set_meta(
			"active_animation_hand_map",
			hand_map.duplicate(true)
		)
		calibrated_pivot.position = vector3_from_map(
			hand_map.get("weapon_mount_position", {}), calibrated_pivot.position
		)
		calibrated_pivot.rotation_degrees = vector3_from_map(
			hand_map.get("weapon_mount_rotation_deg", {}), calibrated_pivot.rotation_degrees
		)
	if left_hand:
		left_hand.position = vector3_from_map(
			hand_map.get("left_grip", hand_map.get("left_hand_target", {})),
			left_hand.position
		)
	if right_hand:
		right_hand.position = vector3_from_map(
			hand_map.get("right_grip", hand_map.get("right_hand_target", {})),
			right_hand.position
		)
	return true


static func restore_animation_hand_map_baseline(
	calibrated_pivot: Node3D,
	left_hand: Marker3D,
	right_hand: Marker3D
) -> void:
	## Remove the previous clip's map without inventing a stance fallback for a
	## raw or unapproved animation.
	_restore_preview_socket_baseline(calibrated_pivot, left_hand, right_hand)


static func _socket(parent: Node3D, socket_name: String, position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = socket_name
	marker.position = position
	marker.set_meta("authored_weapon_socket", true)
	marker.set_meta("canonical_socket_transform", marker.transform)
	parent.add_child(marker)
	return marker


static func _restore_preview_socket_baseline(
	calibrated_pivot: Node3D,
	left_hand: Marker3D,
	right_hand: Marker3D
) -> void:
	if calibrated_pivot and calibrated_pivot.has_meta("canonical_weapon_pivot_transform"):
		calibrated_pivot.transform = calibrated_pivot.get_meta(
			"canonical_weapon_pivot_transform"
		) as Transform3D
		calibrated_pivot.set_meta("active_animation_hand_map", {})
	for marker in [left_hand, right_hand]:
		if marker and marker.has_meta("canonical_socket_transform"):
			marker.transform = marker.get_meta("canonical_socket_transform") as Transform3D


static func _hand_map_key_matches(
	map_key: String,
	lookup_keys: PackedStringArray
) -> bool:
	var normalized_map := _normalized_hand_map_key(map_key)
	for lookup_key in lookup_keys:
		var lookup := String(lookup_key)
		if map_key == lookup or map_key.get_file() == lookup.get_file():
			return true
		var normalized_lookup := _normalized_hand_map_key(lookup)
		if (
			not normalized_map.is_empty()
			and normalized_map == normalized_lookup
		):
			return true
	return false


static func _normalized_hand_map_key(value: String) -> String:
	return (
		value.get_file().get_basename().to_snake_case()
		.replace("rifle_", "")
		.replace("_rifle", "")
	)


static func vector3_from_map(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Dictionary:
		return fallback
	var map := value as Dictionary
	return Vector3(
		float(map.get("x", fallback.x)),
		float(map.get("y", fallback.y)),
		float(map.get("z", fallback.z))
	)


static func _default_model_rotation(model_path: String) -> Vector3:
	return Vector3(0.0, 180.0, 0.0) if "ps1_ak47" in model_path else Vector3(0.0, -90.0, 0.0)


static func _derived_barrel_base(right_grip: Vector3, muzzle: Vector3) -> Vector3:
	var direction := (muzzle - right_grip).normalized()
	if direction.length_squared() < 0.99:
		direction = Vector3.RIGHT
	return muzzle - direction * minf(0.18, maxf(muzzle.distance_to(right_grip) * 0.35, 0.08))


static func _apply_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material(child, material)
