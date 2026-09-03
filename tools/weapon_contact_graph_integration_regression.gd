extends SceneTree

const GunsmithScene := preload("res://gun_calibration_lab.tscn")
const ContactGraph := preload("res://scripts/weapons/weapon_contact_graph_contract.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := GunsmithScene.instantiate()
	if lab.get_script() == null:
		_expect(false, "Gunsmith script compiles and attaches")
		lab.free()
		quit(1)
		return
	root.add_child(lab)
	await process_frame
	await process_frame
	_expect(lab.find_child("TargetPivot", true, false) != null, "original Gunsmith creates shared TargetPivot")
	for node_name in [
		"RHUpperArmWeaponTarget",
		"RHWeaponTarget",
		"LHWeaponContactTarget",
		"SpineTargetWeaponAim",
	]:
		_expect(lab.find_child(node_name, true, false) != null, "Gunsmith creates %s" % node_name)
	var saved: Dictionary = lab.call("_weapon_contact_graph_save_data")
	_expect(bool(saved.get("enabled", false)), "contact graph saves as enabled")
	_expect((saved.get("targets", {}) as Dictionary).size() == 4, "contact graph saves four authored targets")

	var sample := ContactGraph.default_profile()
	ContactGraph.set_target_position_offset(sample, "trigger_hand", Vector3(0.02, -0.01, 0.03))
	ContactGraph.set_target_rotation_offset_degrees(sample, "right_shoulder", Vector3(5.0, -3.0, 2.0))
	var transformed := ContactGraph.apply_offset(Transform3D.IDENTITY, sample, "trigger_hand")
	_expect(transformed.origin.is_equal_approx(Vector3(0.02, -0.01, 0.03)), "runtime contract applies trigger-hand position offset")
	_expect(ContactGraph.target_rotation_offset_degrees(sample, "right_shoulder").is_equal_approx(Vector3(5.0, -3.0, 2.0)), "runtime contract preserves shoulder rotation offset")

	var persistence := FileAccess.get_file_as_string("res://scripts/labs/gunsmith/gunsmith_persistence_controller.gd")
	var runtime := FileAccess.get_file_as_string("res://scripts/player/operator_animation_driver_runtime.gd")
	_expect(persistence.contains("\"weapon_contact_graph\": lab._weapon_contact_graph_save_data()"), "Gunsmith writes the graph into the weapon profile")
	_expect(
		runtime.count("configure_weapon_contact_graph") == 3,
		"canonical runtime configures posture, legacy hand-contact, and TargetPivot consumers"
	)
	lab.queue_free()
	await process_frame
	if failures == 0:
		print("WEAPON_CONTACT_GRAPH_INTEGRATION PASS")
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("CONTACT_GRAPH PASS ", message)
		return
	failures += 1
	push_error("CONTACT_GRAPH FAIL %s" % message)
