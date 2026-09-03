extends SceneTree

const STICK_SCENE := "res://assets/weapons/placeholders/universal_weapon_stick.tscn"
const STATE_SOURCE := "res://scripts/labs/animation_studio/animation_studio_state.gd"
const WEAPON_SOURCE := "res://scripts/labs/animation_studio/animation_studio_weapon.gd"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state_source := _read(STATE_SOURCE)
	var weapon_source := _read(WEAPON_SOURCE)
	var direct_firearm_load := RegEx.new()
	direct_firearm_load.compile(
		"(?:preload|load)\\s*\\(\\s*[\\\"']res://assets/weapons/[^\\\"']+\\.(?:fbx|glb)"
	)
	_expect(
		direct_firearm_load.search(state_source) == null
		and direct_firearm_load.search(weapon_source) == null,
		"Animation Studio has no direct firearm FBX/GLB render load"
	)
	_expect(
		"const UNIVERSAL_WEAPON_STICK_SCENE := preload(" in state_source
		and STICK_SCENE in state_source,
		"Animation Studio preloads the universal stick preview"
	)
	_expect(
		"UNIVERSAL_WEAPON_STICK_SCENE.instantiate()" in weapon_source,
		"AK preview instantiates the universal stick"
	)
	_expect(
		"left_handguard_pos = Vector3(0.0, 0.05, 0.32)" in weapon_source,
		"Animation Studio keeps its authored support-hand socket"
	)

	var packed := load(STICK_SCENE) as PackedScene
	_expect(packed != null, "universal stick preview scene loads")
	if packed != null:
		var preview := packed.instantiate() as Node3D
		_expect(preview != null and preview.name == "UniversalWeaponStick", "stick preview is present")
		if preview != null:
			_expect(
				preview.find_child("BoreStick", true, false) is MeshInstance3D
				and preview.find_child("TriggerGrip", true, false) is MeshInstance3D
				and preview.find_child("SupportGrip", true, false) is MeshInstance3D,
				"stick preview keeps its bore and hand-contact shapes"
			)
			preview.free()

	var studio_scene := load("res://animation_library_lab.tscn") as PackedScene
	_expect(studio_scene != null, "Animation Studio scene loads")
	if studio_scene != null:
		var studio := studio_scene.instantiate()
		root.add_child(studio)
		await process_frame
		await process_frame
		var live_bore := studio.find_child("BoreStick", true, false)
		var live_support_grip := studio.find_child("SupportGrip", true, false)
		_expect(
			live_bore is MeshInstance3D
			and live_support_grip is MeshInstance3D
			and live_bore.get_parent().name == "WeaponMesh",
			"running Animation Studio contains the universal stick preview geometry"
		)
		var canonical_config: Dictionary = studio.get("gunsmith_weapon_config")
		_expect(
			String(canonical_config.get("weapon_id", "")) == "m16a2"
			and String(canonical_config.get("model_fbx", "")).ends_with("AssaultRifle_1.fbx")
			and canonical_config.get("weapon_sockets", {}) is Dictionary,
			"default M16A2 identity, source metadata, and authored sockets stay canonical"
		)
		studio.queue_free()
	_finish()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_STUDIO_WEAPON_PREVIEW PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_STUDIO_WEAPON_PREVIEW FAIL " + label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_STUDIO_WEAPON_PREVIEW_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_STUDIO_WEAPON_PREVIEW_REGRESSION FAIL ", failures)
		quit(1)
