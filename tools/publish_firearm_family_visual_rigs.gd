extends SceneTree

## Publishes model-specific visual rigs for catalog weapons that still have a
## sparse legacy profile. The runtime never measures meshes or guesses sockets;
## it consumes the immutable JSON produced here through WeaponRigContract.

const CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const OUTPUT_DIRECTORY := "res://config/weapon_visual_rigs/"
const ASSIGNMENTS_PATH := "res://config/weapon_family_visual_assignments.json"

const MODEL_SPECS := {
	"res://assets/weapons/modular_pack/Pistol_1.fbx": {
		"id": "family_pistol_1_v3", "revision": 3, "archetype": "pistol",
		"target_length_m": 0.190, "categories": ["Pistols"],
	},
	"res://assets/weapons/modular_pack/Pistol_2.fbx": {
		"id": "family_pistol_2_v3", "revision": 3, "archetype": "pistol",
		"target_length_m": 0.220, "categories": ["Pistols"],
	},
	"res://assets/weapons/modular_pack/Pistol_3.fbx": {
		"id": "family_pistol_3_v3", "revision": 3, "archetype": "pistol",
		"target_length_m": 0.210, "categories": ["Pistols"],
	},
	"res://assets/weapons/modular_pack/Pistol_4.fbx": {
		"id": "family_pistol_4_v3", "revision": 3, "archetype": "pistol",
		"target_length_m": 0.270, "categories": ["Pistols"],
	},
	"res://assets/weapons/modular_pack/Pistol_5.fbx": {
		"id": "family_pistol_5_v3", "revision": 3, "archetype": "pistol",
		"target_length_m": 0.217, "categories": ["Pistols"],
	},
	"res://assets/weapons/modular_pack/Pistol_6.fbx": {
		"id": "family_pistol_6_v3", "revision": 3, "archetype": "pistol",
		"target_length_m": 0.196, "categories": ["Pistols"],
	},
	"res://assets/weapons/modular_pack/SubmachineGun_1.fbx": {
		"id": "family_smg_1_v1", "archetype": "smg",
		"target_length_m": 0.680,
		"categories": ["Submachine Guns", "Assault Rifles"],
	},
	"res://assets/weapons/modular_pack/SubmachineGun_2.fbx": {
		"id": "family_smg_2_v1", "archetype": "smg",
		"target_length_m": 0.790, "categories": ["Submachine Guns"],
	},
	"res://assets/weapons/modular_pack/SubmachineGun_3.fbx": {
		"id": "family_smg_3_v1", "archetype": "smg",
		"target_length_m": 0.500, "categories": ["Submachine Guns"],
	},
	"res://assets/weapons/modular_pack/SubmachineGun_4.fbx": {
		"id": "family_smg_4_v1", "archetype": "smg",
		"target_length_m": 0.550, "categories": ["Submachine Guns"],
	},
	"res://assets/weapons/modular_pack/AssaultRifle2_1.fbx": {
		"id": "family_rifle_552_v1", "archetype": "rifle",
		"target_length_m": 0.730, "categories": ["Assault Rifles", "Machine Guns"],
	},
	"res://assets/weapons/modular_pack/AssaultRifle2_3.fbx": {
		"id": "family_rifle_aks74_v1", "archetype": "rifle",
		"target_length_m": 0.735, "categories": ["Assault Rifles", "Machine Guns"],
	},
	"res://assets/weapons/modular_pack/AssaultRifle2_4.fbx": {
		"id": "family_rifle_m14_v1", "archetype": "rifle",
		"target_length_m": 1.000, "categories": ["Assault Rifles"],
	},
	"res://assets/weapons/modular_pack/AssaultRifle_2.fbx": {
		"id": "family_rifle_2_v1", "archetype": "rifle",
		"target_length_m": 0.840, "categories": ["Assault Rifles"],
	},
	"res://assets/weapons/modular_pack/AssaultRifle_3.fbx": {
		"id": "family_rifle_3_v1", "archetype": "rifle",
		"target_length_m": 0.780, "categories": ["Assault Rifles"],
	},
	"res://assets/weapons/modular_pack/AssaultRifle_4.fbx": {
		"id": "family_rifle_4_v1", "archetype": "rifle",
		"target_length_m": 0.880, "categories": ["Assault Rifles"],
	},
	"res://assets/weapons/modular_pack/AssaultRifle_5.fbx": {
		"id": "family_rifle_5_v1", "archetype": "rifle",
		"target_length_m": 0.840, "categories": ["Assault Rifles"],
	},
	"res://assets/weapons/modular_pack/Bullpup_1.fbx": {
		"id": "family_bullpup_1_v1", "archetype": "bullpup",
		"target_length_m": 0.720, "categories": ["Assault Rifles"],
	},
	"res://assets/weapons/modular_pack/Shotgun_1.fbx": {
		"id": "family_shotgun_1_v2", "revision": 2, "archetype": "shotgun",
		"target_length_m": 0.950, "categories": ["Assault Rifles", "Shotguns"],
		"support_z_m": 0.220,
	},
	"res://assets/weapons/modular_pack/SniperRifle_1.fbx": {
		"id": "family_sniper_1_v2", "revision": 2, "archetype": "sniper",
		"target_length_m": 1.150, "categories": ["Assault Rifles", "Sniper Rifles"],
		# The 1.15 m receiver makes the generic far-forward contact unreachable in
		# crouch. This point remains on the handguard while keeping a natural elbow.
		"support_z_m": 0.220,
	},
	"res://assets/weapons/modular_pack/AssaultRifle2_2.fbx": {
		"id": "family_machinegun_2_v1", "archetype": "rifle",
		"target_length_m": 1, "categories": ["Machine Guns"],
		"support_z_m": 0.220,
	},
	"res://assets/weapons/modular_pack/Shotgun_2.fbx": {
		"id": "family_shotgun_2_v1", "archetype": "shotgun",
		"target_length_m": 1, "categories": ["Shotguns"],
		"support_z_m": 0.220,
	},
	"res://assets/weapons/modular_pack/SniperRifle_2.fbx": {
		"id": "family_sniper_2_v1", "archetype": "sniper",
		"target_length_m": 1.15, "categories": ["Sniper Rifles"],
		"support_z_m": 0.220,
	},
	"res://assets/weapons/modular_pack/SniperRifle_3.fbx": {
		"id": "family_sniper_3_v1", "archetype": "sniper",
		"target_length_m": 1.15, "categories": ["Sniper Rifles"],
		"support_z_m": 0.220,
	},
	"res://assets/weapons/modular_pack/SniperRifle_4.fbx": {
		"id": "family_sniper_4_v1", "archetype": "sniper",
		"target_length_m": 1.1, "categories": ["Sniper Rifles"],
		"support_z_m": 0.220,
	},
}


func _initialize() -> void:
	_publish.call_deferred()


func _publish() -> void:
	var failures: Array[String] = []
	var model_assignments: Dictionary = {}
	var model_paths: Array = MODEL_SPECS.keys()
	model_paths.sort()
	for model_value: Variant in model_paths:
		var model_path := String(model_value)
		var spec := (MODEL_SPECS[model_value] as Dictionary).duplicate(true)
		var packed := load(model_path) as PackedScene
		if packed == null:
			failures.append("model does not load: %s" % model_path)
			continue
		var instance := packed.instantiate() as Node3D
		root.add_child(instance)
		await process_frame
		var raw_bounds := _combined_aabb(instance)
		instance.free()
		if raw_bounds.size.length_squared() <= 0.000001:
			failures.append("model has no measurable mesh: %s" % model_path)
			continue
		var document := _document_for(model_path, spec, raw_bounds)
		var validation := CONTRACT.validate(document, true)
		if not bool(validation.get("ok", false)):
			failures.append("%s: %s" % [model_path, validation.get("errors", [])])
			continue
		var rig_id := String(spec.get("id", ""))
		var rig_path := OUTPUT_DIRECTORY + rig_id + ".json"
		if not _write_immutable_json(rig_path, document):
			failures.append("published rig differs from immutable file: %s" % rig_path)
			continue
		model_assignments[model_path] = {
			"visual_rig_id": rig_id,
			"categories": (spec.get("categories", []) as Array).duplicate(),
		}
		print("FIREARM_FAMILY_RIG PUBLISHED %s" % rig_id)

	var assignment_document := {
		"schema_version": 1,
		"owner": "GunsLab2VisualRigResolver",
		"description": "Published model-specific presentation inherited by sparse firearm profiles; authored weapon rigs retain priority.",
		"excluded_weapon_ids": [
			"designator", "air_to_ground_missile", "exploding_fuel",
		],
		"model_assignments": model_assignments,
	}
	if failures.is_empty() and not _write_json(ASSIGNMENTS_PATH, assignment_document):
		failures.append("could not write %s" % ASSIGNMENTS_PATH)
	if failures.is_empty():
		print(
			"FIREARM_FAMILY_VISUAL_RIG_PUBLISH PASS models=%d" % model_assignments.size()
		)
		quit(0)
	else:
		for failure in failures:
			push_error("FIREARM_FAMILY_VISUAL_RIG_PUBLISH FAIL " + failure)
		quit(1)


func _document_for(model_path: String, spec: Dictionary, raw_bounds: AABB) -> Dictionary:
	var rotation_degrees := Vector3(0.0, -90.0, 0.0)
	var rotation_basis := Basis.from_euler(
		rotation_degrees * PI / 180.0,
		EULER_ORDER_YXZ
	)
	var pivot_bounds := Transform3D(rotation_basis, Vector3.ZERO) * raw_bounds
	var target_length := float(spec.get("target_length_m", 0.82))
	var scale_value := target_length / maxf(pivot_bounds.size.z, 0.001)
	var scaled_bounds := AABB(
		pivot_bounds.position * scale_value,
		pivot_bounds.size * scale_value
	)
	var archetype := String(spec.get("archetype", "rifle"))
	var family := (
		"TWO_HAND_PISTOL"
		if archetype == "pistol"
		else ("LONG_GUN" if archetype in ["shotgun", "sniper"] else "TWO_HAND_RIFLE")
	)
	var visual := {
		"model_fbx": model_path,
		"normalized_scale": scale_value,
		"user_scale_multiplier": 1.0,
		"model_rotation_degrees": _vector_map(rotation_degrees),
		"operator_mount": _operator_mount(archetype),
		"grip_offset": _grip_offset(archetype),
		"weapon_sockets": _weapon_sockets(archetype, scaled_bounds, spec),
		"support_hand_pose": _support_hand_pose(archetype),
		"handling_profile": _handling_profile(family, archetype),
	}
	return {
		"schema_version": 1,
		"visual_rig_id": String(spec.get("id", "")),
		"revision": int(spec.get("revision", 1)),
		"status": "published",
		"source_model_fbx": model_path,
		"family": family,
		"visual": visual,
		"certification": {
			"required_stances": ["STANDING", "CROUCHED"],
			"required_actions": ["aim_idle", "fire_recovery", "reload"],
			"maximum_palm_error_m": 0.01,
			"published_by": "publish_firearm_family_visual_rigs",
		},
		"calibration": {
			"method": "transformed_mesh_bounds_plus_family_contact_template",
			"raw_bounds_position": _vector_map(raw_bounds.position),
			"raw_bounds_size": _vector_map(raw_bounds.size),
			"target_length_m": target_length,
			"resolved_length_m": scaled_bounds.size.z,
		},
	}


func _operator_mount(archetype: String) -> Dictionary:
	return {
		"attachment_mode": "trigger_hand_socket",
		"bone_name": "mixamorig_RightHand",
		"position": {"x": -0.02, "y": 0.08, "z": 0.05},
		"rotation_degrees": {"x": -90.0, "y": 180.0, "z": 0.0},
	}


func _grip_offset(archetype: String) -> Dictionary:
	if archetype == "pistol":
		return {
			"pos_x": 0.0, "pos_y": 0.0, "pos_z": 0.0,
			"rot_x": 0.0, "rot_y": 0.0, "rot_z": 90.0,
		}
	# The current AssaultRifle_1 golden rig establishes the accepted modular-
	# pack-to-Mixamo axis conversion. It is shared, while scale and every physical
	# contact below are measured per model.
	return {
		"pos_x": 0.0798392296,
		"pos_y": -0.0417042524,
		"pos_z": 0.0082135201,
		"rot_x": 4.55,
		"rot_y": 3.0,
		"rot_z": 79.05,
	}


func _weapon_sockets(archetype: String, bounds: AABB, spec: Dictionary) -> Dictionary:
	var minimum := bounds.position
	var maximum := bounds.position + bounds.size
	var center_x := minimum.x + bounds.size.x * 0.5
	var muzzle_y := minimum.y + bounds.size.y * (0.68 if archetype == "pistol" else 0.78)
	var muzzle_z := maximum.z
	var bore_length := clampf((maximum.z - minimum.z) * 0.28, 0.15, 0.23)
	var barrel_base_z := muzzle_z - bore_length
	if archetype == "pistol":
		return {
			"right_hand_grip_target": _vector_map(Vector3.ZERO),
			"left_hand_ik_target": _vector_map(Vector3(-0.035, -0.015, 0.015)),
			"barrel_base_socket": _vector_map(Vector3(center_x, muzzle_y, barrel_base_z)),
			"muzzle_socket": _vector_map(Vector3(center_x, muzzle_y, muzzle_z)),
			"buttstock_socket": _vector_map(Vector3(center_x, -0.03, minimum.z)),
			"ejection_port": _vector_map(Vector3(maximum.x * 0.75, muzzle_y + 0.007, muzzle_z * 0.52)),
			"optic_rail": _vector_map(Vector3(center_x, maximum.y * 0.78, muzzle_z * 0.42)),
		}
	var support_y := minimum.y + bounds.size.y * 0.65
	var support_ratio := 0.52 if archetype == "smg" else 0.58
	var support_min := 0.16 if archetype == "smg" else 0.22
	var support_max := 0.28 if archetype == "smg" else 0.38
	var support_z := clampf(muzzle_z * support_ratio, support_min, support_max)
	if spec.has("support_z_m"):
		support_z = clampf(float(spec.get("support_z_m", support_z)), minimum.z, maximum.z)
	return {
		"right_hand_grip_target": _vector_map(Vector3.ZERO),
		"left_hand_ik_target": _vector_map(Vector3(center_x, support_y, support_z)),
		"barrel_base_socket": _vector_map(Vector3(center_x, muzzle_y, barrel_base_z)),
		"muzzle_socket": _vector_map(Vector3(center_x, muzzle_y, muzzle_z)),
		"buttstock_socket": _vector_map(Vector3(center_x, support_y, minimum.z)),
		"ejection_port": _vector_map(Vector3(maximum.x * 0.72, muzzle_y, clampf(muzzle_z * 0.28, 0.06, 0.20))),
		"optic_rail": _vector_map(Vector3(center_x, minimum.y + bounds.size.y * 0.92, clampf(muzzle_z * 0.12, 0.04, 0.10))),
	}


func _support_hand_pose(archetype: String) -> Dictionary:
	if archetype == "pistol":
		return {
			"palm_pitch_deg": 0.0,
			"palm_yaw_deg": 0.0,
			"palm_roll_deg": 0.0,
			"finger_curl": 0.82,
			"thumb_wrap": 0.72,
		}
	return {
		"palm_pitch_deg": -24.35,
		"palm_yaw_deg": 0.75,
		"palm_roll_deg": 104.75,
		"finger_curl": 1.0,
		"thumb_wrap": 0.70,
	}


func _handling_profile(family: String, archetype: String) -> Dictionary:
	var profile := {
		"family": family,
		"support_hand_required": true,
		"locomotion_family": "PISTOL" if archetype == "pistol" else "RIFLE",
		"dynamic_hold": {
			"animation_carry_limit_m": 0.025,
			"animation_carry_weight": 0.40,
			"animation_drives_ready_hands": true,
			"hand_socket_ik_enabled": false,
			"support_hand_socket_ik_enabled": true,
			"support_hand_ik_blend_seconds": 0.25,
			"right_hand_owns_weapon": true,
			"hand_owned_aim_correction_limit_deg": 32.0,
			"fire_saved_joint_rotations_enabled": false,
			"fire_spine_ccdik_enabled": false,
			"relaxed_idle_upper_body_weight": 0.0,
			"ready_locomotion_inheritance": 0.0,
			"reload_return_blend_seconds": 0.18,
			# Sparse family fallbacks must not pull a guessed stock point into the
			# shoulder. Individually authored AK/M4 stock constraints remain intact.
			"buttstock_constraint": {"enabled": false},
		},
		"ready_aim": {
			"fire_hold_seconds": 1.2,
			"fire_terminal_pose_hold_seconds": 0.12,
		},
	}
	if archetype == "pistol":
		# Same approved stationary pair as Mark23, preserving existing moving
		# sources and every model-specific contact. Publish a new rig revision.
		profile["animation_slots"] = {
			"idle_standing": "pistol_compressed_idle_standing",
			"idle_crouched": "pistol_compressed_idle_crouched",
			"ready_standing": "pistol_recovery_reference_standing",
			"ready_crouched": "pistol_recovery_reference_crouched",
			"idle_standing_moving": "pistol_idle",
			"ready_standing_moving": "pistol_idle",
			"ready_crouched_moving": "pistol_idle_kneeling",
		}
		profile["dynamic_hold"].merge({
			"authored_compressed_idle_enabled": true,
			"procedural_ready_hand_weight": 0.35,
			"procedural_ready_spine_weight": 1.0,
		}, true)
		profile["ready_aim"].merge({
			"compressed_enter_response": 8.0,
			"locomotion_blend_seconds": 0.24,
		}, true)
	return profile


func _combined_aabb(root_node: Node3D) -> AABB:
	var combined := AABB()
	var found := false
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative := root_node.global_transform.affine_inverse() * mesh_instance.global_transform
		var transformed := relative * mesh_instance.get_aabb()
		combined = transformed if not found else combined.merge(transformed)
		found = true
	return combined if found else AABB()


func _write_immutable_json(path: String, document: Dictionary) -> bool:
	if FileAccess.file_exists(path):
		var existing_file := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = (
			JSON.parse_string(existing_file.get_as_text())
			if existing_file != null
			else null
		)
		if not parsed is Dictionary:
			return false
		var existing := parsed as Dictionary
		var validation := CONTRACT.validate(existing, true)
		# Published revisions are immutable. Reusing an ID is valid only when every
		# nested published value matches the freshly generated document. Any changed
		# calibration, contact, or provenance must receive a new _vN ID.
		return (
			bool(validation.get("ok", false))
			and CONTRACT.published_documents_match(existing, document)
		)
	return _write_json(path, document)


func _write_json(path: String, document: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()
	return true


func _vector_map(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
