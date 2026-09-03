extends SceneTree

const MANIFEST_PATH := "res://config/agls_player_framework_port.json"

var failures: Array[String] = []


func _initialize() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	_expect(file != null, "AGLS player-framework manifest loads")
	if file == null:
		_finish()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_expect(parsed is Dictionary, "AGLS player-framework manifest is valid JSON")
	if not parsed is Dictionary:
		_finish()
		return
	var manifest := parsed as Dictionary
	var rig: Dictionary = manifest.get("rig", {})
	_expect(bool(rig.get("strict_authored_pose", false)), "AGLS owns the authored body pose")
	var disabled: Array = rig.get("disabled_legacy_corrections", [])
	for correction in [
		"square_shoulders",
		"procedural_arm_placement",
		"procedural_hand_placement",
		"procedural_weapon_pose",
		"foot_contact_lock",
	]:
		_expect(disabled.has(correction), "legacy correction %s stays disabled" % correction)
	var protected: Dictionary = manifest.get("protected_socom_owners", {})
	for system_name in [
		"camera_and_mouse_string_aim",
		"reticle_and_feedback",
		"weapon_input_and_ammunition",
		"ballistics_and_dispersion",
		"hurtboxes_and_damage",
		"shot_authority",
		"multiplayer_combat",
		"authoritative_body",
	]:
		_expect(protected.has(system_name), "SOCOM owner %s is protected" % system_name)
	var expected_modules := [
		"ground_locomotion", "stance", "jump_and_landing", "roll_and_dive",
		"mantle_and_vault", "free_climbing", "ladder", "rope", "zipline",
		"swimming", "narrow_ledge", "weapon_equip", "weapon_reload",
		"weapon_recoil_presentation", "weapon_pickup", "grenade_presentation",
		"wheel_and_valve", "workbench",
	]
	var module_ids: Array[String] = []
	for raw_module in manifest.get("modules", []):
		if raw_module is Dictionary:
			module_ids.append(String(raw_module.get("id", "")))
	for module_id in expected_modules:
		_expect(module_ids.has(module_id), "AGLS migration includes %s" % module_id)
	_expect(
		ResourceLoader.exists(String(rig.get("config", "")))
		and ResourceLoader.exists(String(rig.get("animation_map", ""))),
		"live AGLS rig and animation map are referenced"
	)
	_expect(
		FileAccess.file_exists(
			"res://assets/external/agls_intake/imported/interaction_workbench/SM_Workbench.glb"
		),
		"AGLS workbench presentation source is available for Godot import"
	)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_FRAMEWORK_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_FRAMEWORK_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_PLAYER_FRAMEWORK_PORT_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_PLAYER_FRAMEWORK_PORT_REGRESSION FAIL %s" % [failures])
	quit(1)
