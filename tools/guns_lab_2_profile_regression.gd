extends SceneTree

const CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const REPOSITORY := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_repository.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var source := _read_json("res://config/weapons/assaultrifle_1.json")
	_expect(not source.is_empty(), "AssaultRifle_1 golden source profile loads")
	var draft := CONTRACT.extract(source, "assaultrifle_1", 1, "draft")
	var visual: Dictionary = draft.get("visual", {})
	_expect(not visual.has("ballistics"), "visual rig excludes ballistics")
	_expect(not visual.has("fire_modes"), "visual rig excludes fire modes")
	_expect(not visual.has("weapon_id"), "visual rig excludes weapon identity")
	_expect(
		String(visual.get("model_fbx", "")).ends_with("AssaultRifle_1.fbx"),
		"visual rig keeps the exact calibrated mesh"
	)
	var validation := CONTRACT.validate(draft, false)
	_expect(bool(validation.get("ok", false)), "golden source produces a valid draft")

	var published := draft.duplicate(true)
	published["visual_rig_id"] = "assaultrifle_1_v1"
	published["status"] = "published"
	var round_trip_value: Variant = JSON.parse_string(JSON.stringify(published))
	var round_trip := (
		(round_trip_value as Dictionary)
		if round_trip_value is Dictionary
		else {}
	)
	_expect(
		CONTRACT.published_documents_match(published, round_trip),
		"immutable comparison accepts an identical disk round trip"
	)
	var changed_published := published.duplicate(true)
	var changed_visual: Dictionary = changed_published.get("visual", {})
	var changed_sockets: Dictionary = changed_visual.get("weapon_sockets", {})
	var changed_support: Dictionary = changed_sockets.get("left_hand_ik_target", {})
	changed_support["x"] = float(changed_support.get("x", 0.0)) + 0.001
	_expect(
		not CONTRACT.published_documents_match(published, changed_published),
		"immutable comparison rejects a nested socket change under the same ID"
	)
	var malformed_grip := published.duplicate(true)
	(malformed_grip.get("visual", {}) as Dictionary)["grip_offset"] = []
	_expect(
		not bool(CONTRACT.validate(malformed_grip, true).get("ok", false)),
		"published validation rejects a non-dictionary grip offset"
	)
	var malformed_rotation := published.duplicate(true)
	(malformed_rotation.get("visual", {}) as Dictionary)["model_rotation_degrees"] = {
		"x": "ninety", "y": 0.0, "z": 0.0,
	}
	_expect(
		not bool(CONTRACT.validate(malformed_rotation, true).get("ok", false)),
		"published validation rejects non-numeric transform components"
	)
	var malformed_handling := published.duplicate(true)
	(malformed_handling.get("visual", {}) as Dictionary)["handling_profile"] = []
	_expect(
		not bool(CONTRACT.validate(malformed_handling, true).get("ok", false)),
		"published validation rejects a non-dictionary handling profile"
	)
	var uncertified := published.duplicate(true)
	uncertified.erase("certification")
	_expect(
		not bool(CONTRACT.validate(uncertified, true).get("ok", false)),
		"published validation requires certification metadata"
	)
	_expect(
		not bool(
			CONTRACT.validate(published, true, "different_visual_rig_v1").get("ok", false)
		),
		"published validation binds a document to its requested ID"
	)
	var weapon := {
		"weapon_id": "test_m16",
		"display_name": "Test M16",
		"ballistics": {"damage": 91.0, "fire_rate_rpm": 777.0},
		"fire_modes": ["semi", "burst"],
		"model_fbx": "res://assets/weapons/modular_pack/AssaultRifle_2.fbx",
		"normalized_scale": 9.0,
	}
	var resolved := CONTRACT.merge_for_presentation(weapon, published)
	_expect(
		float((resolved.ballistics as Dictionary).damage) == 91.0,
		"visual merge cannot change damage"
	)
	_expect(
		float((resolved.ballistics as Dictionary).fire_rate_rpm) == 777.0,
		"visual merge cannot change cadence"
	)
	_expect(resolved.fire_modes == ["semi", "burst"], "visual merge cannot change fire modes")
	_expect(String(resolved.weapon_id) == "test_m16", "visual merge cannot change identity")
	_expect(
		String(resolved.model_fbx).ends_with("AssaultRifle_1.fbx"),
		"visual merge applies the golden mesh"
	)

	var token := str(Time.get_ticks_usec())
	var root_path := "user://guns_lab_2_profile_regression_%s/" % token
	var published_path := root_path + "published/"
	var draft_path := root_path + "drafts/"
	var weapon_path := root_path + "weapons/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(weapon_path))
	_write_json(weapon_path + "test_m16.json", weapon)
	var repository = REPOSITORY.new(published_path, draft_path, weapon_path)
	var saved: Dictionary = repository.save_draft("assaultrifle_1", source)
	_expect(bool(saved.get("ok", false)), "repository saves a visual-only draft")
	var promoted: Dictionary = repository.publish("assaultrifle_1")
	_expect(bool(promoted.get("ok", false)), "repository publishes the first golden version")
	_expect(
		String(promoted.get("visual_rig_id", "")) == "assaultrifle_1_v1",
		"first published profile receives v1"
	)
	var assignment: Dictionary = repository.assign_to_weapon(
		"test_m16",
		"assaultrifle_1_v1"
	)
	_expect(bool(assignment.get("ok", false)), "published visual rig assigns to a weapon")
	var assigned := _read_json(weapon_path + "test_m16.json")
	_expect(
		String(assigned.get("visual_rig_id", "")) == "assaultrifle_1_v1",
		"assignment stores only the visual-rig reference"
	)
	_expect(
		float((assigned.ballistics as Dictionary).damage) == 91.0,
		"assignment preserves gameplay damage"
	)
	_expect(
		assigned.fire_modes == ["semi", "burst"],
		"assignment preserves gameplay modes"
	)
	var mislabeled := (promoted.get("document", {}) as Dictionary).duplicate(true)
	_write_json(published_path + "mislabeled_v1.json", mislabeled)
	var mismatched_assignment: Dictionary = repository.assign_to_weapon(
		"test_m16",
		"mislabeled_v1"
	)
	_expect(
		not bool(mismatched_assignment.get("ok", false)),
		"repository rejects a published file whose internal ID does not match"
	)
	var promoted_again: Dictionary = repository.publish("assaultrifle_1")
	_expect(
		String(promoted_again.get("visual_rig_id", "")) == "assaultrifle_1_v2",
		"later publication creates a new immutable version"
	)
	_finish()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  "))


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GUNS_LAB_2_PROFILE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("GUNS_LAB_2_PROFILE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("GUNS_LAB_2_PROFILE_REGRESSION PASS")
		quit(0)
	else:
		print("GUNS_LAB_2_PROFILE_REGRESSION FAIL ", failures)
		quit(1)
