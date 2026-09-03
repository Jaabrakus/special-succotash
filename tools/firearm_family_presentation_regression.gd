extends SceneTree

const WEAPON_DIRECTORY := "res://config/weapons"
const INCLUDED_CATEGORIES := {
	"Pistols": true,
	"Assault Rifles": true,
	"Submachine Guns": true,
}
const EXCLUDED_WEAPON_IDS := {
	"designator": true,
	"air_to_ground_missile": true,
	"exploding_fuel": true,
}
const REQUIRED_SOCKET_FIELDS: Array[String] = [
	"right_hand_grip_target",
	"left_hand_ik_target",
	"barrel_base_socket",
	"muzzle_socket",
	"buttstock_socket",
	"ejection_port",
	"optic_rail",
]
const PISTOL_LENGTH_RANGE_M := Vector2(0.16, 0.35)
const SUBMACHINE_GUN_LENGTH_RANGE_M := Vector2(0.35, 0.85)
const RIFLE_LENGTH_RANGE_M := Vector2(0.45, 1.20)
const LONG_GUN_LENGTH_RANGE_M := Vector2(0.65, 1.50)

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)
const VisualRigContract := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const VisualRigResolver := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd"
)

var failures: Array[String] = []
var checked_weapon_ids: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var paths := _collect_firearm_paths()
	_expect(paths.size() >= 30, "all saved pistol, rifle, and SMG profiles are discovered")
	for path in paths:
		_check_weapon(path)
	_expect(
		not checked_weapon_ids.has("designator")
		and not checked_weapon_ids.has("air_to_ground_missile")
		and not checked_weapon_ids.has("exploding_fuel"),
		"non-firearm catalog placeholders stay outside the family presentation gate"
	)
	_finish()


func _collect_firearm_paths() -> Array[String]:
	var paths: Array[String] = []
	for file_name in DirAccess.get_files_at(WEAPON_DIRECTORY):
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [WEAPON_DIRECTORY, file_name]
		var raw := _read_dictionary(path)
		if raw.is_empty() or not INCLUDED_CATEGORIES.has(String(raw.get("category", ""))):
			continue
		var weapon_id := String(raw.get("weapon_id", file_name.get_basename()))
		if EXCLUDED_WEAPON_IDS.has(weapon_id):
			continue
		paths.append(path)
	paths.sort()
	return paths


func _check_weapon(path: String) -> void:
	var raw := _read_dictionary(path)
	var config := WeaponContract.load_config(path)
	var weapon_id := String(raw.get("weapon_id", path.get_file().get_basename()))
	checked_weapon_ids.append(weapon_id)
	_expect(not config.is_empty(), "%s loads through SocomWeaponRigContract" % weapon_id)
	if config.is_empty():
		return

	var expected_family := _expected_family(raw)
	var handling: Dictionary = config.get("handling_profile", {})
	_expect(
		String(handling.get("family", "")) == expected_family,
		"%s resolves to independently expected family %s" % [weapon_id, expected_family]
	)
	if expected_family == WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL:
		var grip_offset: Dictionary = config.get("grip_offset", {})
		_expect(
			is_equal_approx(float(grip_offset.get("rot_z", INF)), 90.0),
			"%s uses the certified optic-up pistol roll" % weapon_id
		)

	_expect(
		_has_saved_authored_socket_source(raw, config),
		"%s resolves all seven physical sockets from saved authored data" % weapon_id
	)

	var configured_length := _configured_model_length(config)
	var expected_range := _expected_length_range(raw, expected_family)
	_expect(
		configured_length >= expected_range.x and configured_length <= expected_range.y,
		"%s mesh length %.4f m is within %.2f-%.2f m" % [
			weapon_id,
			configured_length,
			expected_range.x,
			expected_range.y,
		]
	)

	var dynamic_hold: Dictionary = handling.get("dynamic_hold", {})
	_expect(
		not bool(dynamic_hold.get("hand_socket_ik_enabled", true))
		and bool(dynamic_hold.get("support_hand_socket_ik_enabled", false))
		and bool(dynamic_hold.get("right_hand_owns_weapon", false)),
		"%s keeps trigger-hand weapon ownership with support-hand-only IK" % weapon_id
	)
	_expect(
		bool(handling.get("standing_fire_uses_aim_idle", false))
		and bool(handling.get("crouched_fire_uses_aim_idle", false)),
		"%s preserves standing and crouched recovery without a fire OneShot" % weapon_id
	)


func _expected_family(raw: Dictionary) -> String:
	var category := String(raw.get("category", ""))
	if category == "Pistols":
		return WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL
	var searchable := " ".join([
		String(raw.get("weapon_id", "")),
		String(raw.get("display_name", "")),
		String(raw.get("model_fbx", "")),
	]).to_lower()
	if "shotgun" in searchable or "sniper" in searchable:
		return WeaponAnimationProfile.FAMILY_LONG_GUN
	return WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE


func _has_saved_authored_socket_source(raw: Dictionary, config: Dictionary) -> bool:
	if bool(raw.get("socket_contract_authored", false)):
		return _has_all_socket_vectors(raw.get("weapon_sockets", {}))
	var visual_rig_id := String(config.get("_visual_rig_id", "")).strip_edges()
	if visual_rig_id.is_empty():
		return false
	var visual_rig := VisualRigResolver.load_published(visual_rig_id)
	if visual_rig.is_empty():
		return false
	var validation := VisualRigContract.validate(visual_rig, true)
	if not bool(validation.get("ok", false)):
		return false
	var visual: Dictionary = visual_rig.get("visual", {})
	return (
		String(visual_rig.get("visual_rig_id", "")) == visual_rig_id
		and String(visual_rig.get("status", "")) == "published"
		and _has_all_socket_vectors(visual.get("weapon_sockets", {}))
		and _has_all_socket_vectors(config.get("weapon_sockets", {}))
	)


func _has_all_socket_vectors(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var sockets := value as Dictionary
	for socket_name in REQUIRED_SOCKET_FIELDS:
		if not sockets.has(socket_name) or not _is_vector3_map(sockets[socket_name]):
			return false
	return true


func _expected_length_range(raw: Dictionary, expected_family: String) -> Vector2:
	if expected_family == WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL:
		return PISTOL_LENGTH_RANGE_M
	if expected_family == WeaponAnimationProfile.FAMILY_LONG_GUN:
		return LONG_GUN_LENGTH_RANGE_M
	var searchable := " ".join([
		String(raw.get("weapon_id", "")),
		String(raw.get("display_name", "")),
		String(raw.get("category", "")),
		String(raw.get("model_fbx", "")),
	]).to_lower()
	if "submachine" in searchable or "smg" in searchable:
		return SUBMACHINE_GUN_LENGTH_RANGE_M
	return RIFLE_LENGTH_RANGE_M


func _configured_model_length(config: Dictionary) -> float:
	var model_path := String(config.get("model_fbx", ""))
	var packed := load(model_path) as PackedScene
	if packed == null:
		return 0.0
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return 0.0
	var length := _node_bounds_longest_axis(instance) * float(
		config.get("normalized_scale", 1.0)
	)
	instance.free()
	return length


func _node_bounds_longest_axis(node: Node3D) -> float:
	var bounds := AABB()
	var initialized := false
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.mesh.get_aabb()
		var to_root := _transform_to_ancestor(node, mesh_instance)
		for x in [local_bounds.position.x, local_bounds.end.x]:
			for y in [local_bounds.position.y, local_bounds.end.y]:
				for z in [local_bounds.position.z, local_bounds.end.z]:
					var point := to_root * Vector3(x, y, z)
					if initialized:
						bounds = bounds.expand(point)
					else:
						bounds = AABB(point, Vector3.ZERO)
						initialized = true
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) if initialized else 0.0


func _transform_to_ancestor(ancestor: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if not cursor is Node3D:
			return Transform3D.IDENTITY
		result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result


func _is_vector3_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var vector := value as Dictionary
	return vector.has("x") and vector.has("y") and vector.has("z")


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var value: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("FIREARM_FAMILY_PRESENTATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("FIREARM_FAMILY_PRESENTATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print(
			"FIREARM_FAMILY_PRESENTATION_REGRESSION PASS weapons=%d"
			% checked_weapon_ids.size()
		)
		quit(0)
		return
	print("FIREARM_FAMILY_PRESENTATION_REGRESSION FAIL ", failures)
	quit(1)
