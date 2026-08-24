extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "playable scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in 50:
		await process_frame
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var weapon := driver.get("weapon_node") as Node3D if driver != null else null
	var solver: Variant = driver.get("weapon_pose_solver") if driver != null else null
	var grip: Variant = driver.get("weapon_grip_contact") if driver != null else null
	_expect(driver != null and weapon != null and solver != null, "weapon presentation runtime is live")
	_expect(grip != null, "runtime grip contact is installed")
	if driver == null or weapon == null or solver == null or grip == null:
		_finish()
		return
	var owner_state: Dictionary = solver.call("get_weapon_presentation_owner_state")
	var grip_state: Dictionary = grip.call("snapshot")
	print("WEAPON_PRESENTATION_METRIC owner=%s parent=%s visible=%s grip=%s" % [
		String(owner_state.get("owner", "")),
		String(owner_state.get("parent", "")),
		str(owner_state.get("visible", false)),
		str(grip_state),
	])
	_expect(
		StringName(owner_state.get("owner", &"")) == &"RELAXED_RIFLE_LOCOMOTION",
		"relaxed rifle has one declared owner"
	)
	_expect(
		String(owner_state.get("parent", "")) == "AK47_Attachment",
		"relaxed rifle returns to the authored right-hand mount"
	)
	_expect(bool(owner_state.get("visible", false)), "owner keeps the equipped rifle visible")
	_expect(
		bool(grip_state.get("right_grip_applied", false))
		and bool(grip_state.get("left_grip_applied", false))
		and int(grip_state.get("bone_count", 0)) >= 24,
		"two-hand rifle wraps both palms with the operator finger bones"
	)
	grip.call("apply", &"GRENADE_ACTION", &"ANIMATION_FREE", true)
	grip_state = grip.call("snapshot")
	_expect(
		not bool(grip_state.get("right_grip_applied", true))
		and not bool(grip_state.get("left_grip_applied", true)),
		"grenade action releases rifle finger wrapping"
	)
	scene.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_PRESENTATION_CHECK PASS %s" % label)
	else:
		failures.append(label)
		push_error("WEAPON_PRESENTATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_PRESENTATION_OWNER_REGRESSION PASS")
		quit(0)
	else:
		push_error("WEAPON_PRESENTATION_OWNER_REGRESSION FAIL %s" % [failures])
		quit(1)
