extends SceneTree

const Profile := preload("res://scripts/camera/camera_profile.gd")
const Hybrid := preload("res://scripts/camera/camera_source_hybrid.gd")
const Rig := preload("res://scripts/camera/socom_camera.gd")
var failures: Array[String] = []

func _init() -> void:
	var profile := Profile.new()
	var defaults := _protected(profile)
	_expect(not Hybrid.configure(profile), "trial disabled by default")
	_expect(Hybrid.open_distance(profile) == profile.distance, "default distance identical")
	_expect(Hybrid.configure(profile, true), "saved trial loads")
	_expect(is_equal_approx(profile.source_camera_distance_m, 3.0), "source full distance times verified world scale")
	_expect(is_equal_approx(Hybrid.open_distance(profile), 2.36), "unit-based target plus authored 20 percent calibration")
	_expect(_protected(profile) == defaults, "existing profile properties preserved")
	var original_height: float = profile.height
	profile.height = 10.0
	_expect(is_equal_approx(Hybrid.open_distance(profile), 2.36), "trial distance independent of our anchor or height")
	profile.height = original_height
	profile.source_camera_mix = 100.0
	profile.source_camera_max_distance_delta_m = 100.0
	_expect(Hybrid.open_distance(profile) <= profile.distance + 0.600001, "hard distance delta cap")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Hybrid.SETTINGS_PATH))
	var old_schema: Dictionary = saved.duplicate(true)
	old_schema.schema_version = 1
	var malformed_settings: Array = [{}, old_schema, {"schema_version": 2, "source": [], "hybrid": {}}]
	for field in ["cam_full_dist", "world_meters_per_unit"]:
		for bad in [null, 0.0, -0.1, "0.1", INF, NAN, 1.0e300]:
			var invalid: Dictionary = saved.duplicate(true)
			invalid.source[field] = bad
			malformed_settings.append(invalid)
	for field in ["mix", "max_distance_delta_m"]:
		for bad in [null, "0.2", INF, NAN]:
			var invalid: Dictionary = saved.duplicate(true)
			invalid.hybrid[field] = bad
			malformed_settings.append(invalid)
	for malformed in malformed_settings:
		_expect(not Hybrid.apply_settings(profile, malformed, true), "invalid data rejected")
		_expect(Hybrid.open_distance(profile) == profile.distance, "invalid data restores default")
	_expect(_protected(profile) == defaults, "invalid data preserves protected properties")
	_expect(Hybrid.apply_settings(profile, saved, true), "valid data restores trial after failures")
	_expect(not Hybrid.apply_settings(profile, saved, false), "normal load disables prior forced trial")
	_expect(Hybrid.open_distance(profile) == profile.distance, "off-default parity after forced trial")
	Hybrid.apply_settings(profile, saved, true)
	profile.source_camera_distance_m = NAN
	_expect(Hybrid.open_distance(profile) == profile.distance, "corrupt runtime distance fails closed")
	call_deferred("_solver_proof")

func _solver_proof() -> void:
	var rig := Rig.new()
	rig.capture_mouse_on_ready = false
	root.add_child(rig)
	var target := Node3D.new()
	root.add_child(target)
	rig.target = target
	var baseline: Vector3 = rig.preferred_shot_solver.preferred_position()
	Hybrid.configure(rig.profile, true)
	var candidate: Vector3 = rig.preferred_shot_solver.preferred_position()
	_expect(candidate.z > baseline.z and candidate.y == baseline.y and candidate.x == baseline.x, "solver consumes distance only")
	for state in ["interior_amount", "downward_crane_amount"]:
		rig.set(state, 1.0)
		var trial: Vector3 = rig.preferred_shot_solver.preferred_position()
		rig.profile.source_camera_mix = 0.0
		_expect(trial.is_equal_approx(rig.preferred_shot_solver.preferred_position()), "protected full state: " + state)
		Hybrid.configure(rig.profile, true)
		rig.set(state, 0.0)
	rig.free()
	target.free()
	print("CAMERA_SOURCE_HYBRID ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _protected(profile: Resource) -> Dictionary:
	var result := {}
	for property in profile.get_property_list():
		var key := str(property.name)
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not key.begins_with("source_camera_"):
			result[key] = profile.get(key)
	return result

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("CAMERA_SOURCE_HYBRID " + label)
