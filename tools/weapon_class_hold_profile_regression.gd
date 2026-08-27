extends SceneTree

const ClassHoldProfile := preload(
	"res://scripts/weapons/weapon_class_hold_profile.gd"
)
const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	var raw_m4 := _read_json("res://config/weapons/m4a1.json")
	var m4 := ClassHoldProfile.apply_to_config(raw_m4)
	_expect_geometry_unchanged(raw_m4, m4, "M4A1")
	var m4_handling: Dictionary = m4.get("handling_profile", {})
	_expect(
		String(m4_handling.get("class_id", "")) == ClassHoldProfile.CLASS_ASSAULT_RIFLE,
		"M4A1 resolves to the assault-rifle hold class"
	)
	_expect(
		String(m4_handling.get("class_pose_source", "")) == "AssaultRifle_1",
		"M4A1 inherits the verified AssaultRifle_1 pose source"
	)
	_expect(
		String(m4_handling.get("family", "")) == WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE,
		"M4A1 uses the two-hand rifle animation family"
	)
	_expect(
		String((m4_handling.get("locomotion_slots", {}) as Dictionary).get("jump", ""))
		== "rifle_jump",
		"moving assault rifles retain the verified rifle jump"
	)
	var target_left: Dictionary = (raw_m4.get("weapon_sockets", {}) as Dictionary).get(
		"left_hand_ik_target", {}
	)
	var inherited_standing: Dictionary = (m4.get("stances", {}) as Dictionary).get("STANDING", {})
	var inherited_aim: Dictionary = (m4.get("animation_hand_maps", {}) as Dictionary).get("aim_idle", {})
	_expect(
		_vector(inherited_standing.get("left_grip", {})).is_equal_approx(_vector(target_left)),
		"inherited standing pose follows the M4A1 support-hand socket"
	)
	_expect(
		_vector(inherited_aim.get("left_grip", {})).is_equal_approx(_vector(target_left)),
		"inherited Aim Idle follows the M4A1 support-hand socket"
	)
	_expect(
		not (m4.get("animation_frame_pose_keys", {}) as Dictionary).has("reload"),
		"class inheritance does not copy AssaultRifle_1 reload geometry"
	)

	var raw_pistol := _read_json("res://config/weapons/m9.json")
	var pistol := ClassHoldProfile.apply_to_config(raw_pistol)
	_expect_geometry_unchanged(raw_pistol, pistol, "M9")
	var pistol_handling: Dictionary = pistol.get("handling_profile", {})
	var pistol_slots: Dictionary = pistol_handling.get("animation_slots", {})
	var pistol_locomotion: Dictionary = pistol_handling.get("locomotion_slots", {})
	_expect(
		String(pistol_handling.get("class_id", "")) == ClassHoldProfile.CLASS_PISTOL
		and String(pistol_handling.get("family", "")) == WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL,
		"M9 resolves to the classified pistol animation family"
	)
	_expect(
		String(pistol_slots.get("idle_standing", "")) == "pistol_idle"
		and String(pistol_slots.get("idle_crouched", "")) == "pistol_idle_kneeling"
		and String(pistol_locomotion.get("run_forward", "")) == "pistol_run_forward",
		"pistol idle, crouch, and movement clips remain connected"
	)
	_expect(
		(pistol.get("animation_frame_pose_keys", {}) as Dictionary).is_empty(),
		"pistols do not inherit rifle frame poses"
	)

	var m40 := ClassHoldProfile.apply_to_config(_read_json("res://config/weapons/m40a1.json"))
	_expect(
		String((m40.get("handling_profile", {}) as Dictionary).get("class_id", ""))
		== ClassHoldProfile.CLASS_SNIPER_RIFLE,
		"M40A1 catalog mismatch is corrected to the sniper class"
	)
	_finish()


func _expect_geometry_unchanged(before: Dictionary, after: Dictionary, label: String) -> void:
	for field in [
		"normalized_scale", "user_scale_multiplier", "model_rotation_degrees",
		"operator_mount", "grip_offset", "weapon_sockets",
	]:
		_expect(before.get(field) == after.get(field), "%s preserves %s" % [label, field])


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _vector(value: Variant) -> Vector3:
	if not value is Dictionary:
		return Vector3.ZERO
	var map := value as Dictionary
	return Vector3(
		float(map.get("x", 0.0)),
		float(map.get("y", 0.0)),
		float(map.get("z", 0.0))
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_CLASS_HOLD_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_CLASS_HOLD_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_CLASS_HOLD_PROFILE_REGRESSION PASS")
		quit(0)
	else:
		print("WEAPON_CLASS_HOLD_PROFILE_REGRESSION FAIL ", failures)
		quit(1)
