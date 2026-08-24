extends SceneTree

const Ownership := preload("res://scripts/player/weapon_ownership_contract.gd")
const CompatibilityOwnership := preload(
	"res://scripts/player/operator_weapon_ownership_contract.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ready_owner := Ownership.resolve(&"STANDING", &"", 1.0, false)
	var ready_preview := Ownership.preview_policy("idle_standing")
	_expect(ready_owner == Ownership.READY_SOLVER, "ready gameplay selects the weapon solver")
	_expect(
		StringName(ready_preview.get("resolved_owner", &"")) == ready_owner,
		"Gunsmith ready preview uses the gameplay owner"
	)

	var reload_owner := Ownership.resolve(&"STANDING", &"reload", 1.0, false)
	var reload_preview := Ownership.preview_policy("reload_standing", &"reload")
	_expect(reload_owner == Ownership.RELOAD_RIGHT_HAND, "reload gives the right hand rifle ownership")
	_expect(
		StringName(reload_preview.get("resolved_owner", &"")) == reload_owner,
		"Gunsmith reload preview uses the gameplay owner"
	)
	_expect(
		StringName(reload_preview.get("support_hand", &""))
		== Ownership.SUPPORT_ANIMATION_FREE,
		"reload releases support-hand IK until regrip"
	)

	for locomotion_clip in [
		&"rifle sprint right",
		&"prone forward",
		&"moving backward in crawl position",
		&"walk crouching forward",
	]:
		var locomotion_preview := Ownership.preview_policy("", locomotion_clip)
		_expect(
			StringName(locomotion_preview.get("resolved_owner", &""))
			== Ownership.RELAXED_RIFLE_LOCOMOTION,
			"%s previews the authored relaxed-rifle pose" % locomotion_clip
		)
	var relaxed_idle_preview := Ownership.preview_policy("idle_standing", &"rifle idle")
	_expect(
		StringName(relaxed_idle_preview.get("resolved_owner", &""))
		== Ownership.RELAXED_RIFLE_LOCOMOTION,
		"plain rifle idle previews the authored relaxed-rifle pose"
	)
	_expect(
		StringName(relaxed_idle_preview.get("support_hand", &""))
		== Ownership.SUPPORT_IK_TO_WEAPON,
		"relaxed rifle locomotion keeps the support palm on the saved foregrip"
	)
	for mobility_clip in [&"jump forward", &"jump shooting rifle", &"running dive roll"]:
		var mobility_preview := Ownership.preview_policy("fire_standing", mobility_clip)
		_expect(
			StringName(mobility_preview.get("resolved_owner", &""))
			== Ownership.MOBILITY_CHEST_CARRY,
			"%s keeps full-body motion with stable chest rifle ownership" % mobility_clip
		)

	var grenade_owners := Ownership.resolve_pose_owners(
		&"STANDING", &"grenade_toss", 1.0, false, false, &"STANDING"
	)
	_expect(
		StringName(grenade_owners.get("weapon", &"")) == Ownership.GRENADE_ACTION,
		"grenade animation owns its visual action regions"
	)
	_expect(
		StringName(grenade_owners.get("aim", &"")) == Ownership.AIM_CAMERA_RETICLE
		and StringName(grenade_owners.get("shot", &"")) == Ownership.SHOT_SERVER_WEAPON
		and StringName(grenade_owners.get("authoritative_body", &"")) == Ownership.BODY_CHARACTER,
		"visual animation never owns body, aim, or shot authority"
	)
	_expect(
		Ownership.ownership_conflicts(grenade_owners).is_empty(),
		"complete ownership snapshot has no missing or illegal owner"
	)
	var invalid := grenade_owners.duplicate(true)
	invalid["shot"] = &"ACTION_CLIP"
	_expect(
		not Ownership.ownership_conflicts(invalid).is_empty(),
		"ownership audit detects visual shot-authority conflicts"
	)

	_expect(
		CompatibilityOwnership.resolve(&"DIVING", &"", 1.0, false)
		== Ownership.resolve(&"DIVING", &"", 1.0, false),
		"legacy ownership path delegates to the shared resolver"
	)
	var solver_source := _read("res://scripts/player/operator_weapon_pose_solver.gd")
	var solver_state_source := _read("res://scripts/player/operator_weapon_pose_state.gd")
	var gunsmith_source := _read("res://scripts/labs/gun_calibration_lab.gd")
	var gunsmith_dependencies_source := _read(
		"res://scripts/labs/gunsmith/gunsmith_lab_dependencies.gd"
	)
	_expect(
		"operator_weapon_pose_api.gd" in solver_source
		and "res://scripts/player/weapon_ownership_contract.gd" in solver_state_source,
		"componentized gameplay pose solver imports the shared contract once"
	)
	_expect(
		"gunsmith_lab_preview_api.gd" in gunsmith_source
		and "res://scripts/player/weapon_ownership_contract.gd" in gunsmith_dependencies_source,
		"componentized Gunsmith imports the shared contract once through its dependency layer"
	)
	if failures.is_empty():
		print("POSE_OWNERSHIP_CONTRACT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("POSE_OWNERSHIP_CHECK FAIL %s" % failure)
	quit(1)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
