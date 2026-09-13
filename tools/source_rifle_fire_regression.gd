extends SceneTree

const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()

func _run() -> void:
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	for gun in ["ak-47", "m4a1", "mark_23"]:
		check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/" + gun + ".json")), gun + " equips")
		var graph = driver.locomotion_graph
		for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
			var protected: bool = gun != "mark_23" and posture != &"PRONE"
			var before: int = graph.fire_trigger_count
			check(graph.trigger_fire(posture) != &"", "accepted presentation event remains available")
			check(graph.fire_trigger_count == before + 1, "event is not swallowed")
			check(graph.source_rifle_fire_pose(posture) == protected, "source policy does not leak into pistol/prone")
			if protected:
				check(graph.fire_layer_node.filter_enabled, "source protection uses enabled filter")
				for bone: StringName in graph.UPPER_BODY_BONES:
					check(not graph.fire_layer_node.is_path_filtered(NodePath(".:%s" % bone)), "shot leaves source bone " + String(bone))
			else:
				# The shared reload/stance contract now optionally plants prone arms.
				# Accepted prone fire still runs, but must not flap those arm tracks.
				var stable_prone: bool = posture == &"PRONE" and bool(graph.crouched_reload_pose.settings.stable_prone_fire_arms)
				check(graph.fire_layer_node.is_path_filtered(NodePath(".:mixamorig_RightArm")) == not stable_prone, gun + " " + String(posture) + " respects saved prone-arm policy")
				if posture == &"PRONE":
					graph.crouched_reload_pose.settings.stable_prone_fire_arms = not stable_prone
					graph._configure_fire_filter(posture)
					check(graph.fire_layer_node.is_path_filtered(NodePath(".:mixamorig_RightArm")) == stable_prone, gun + " prone-arm policy remains configurable")
					graph.crouched_reload_pose.settings.stable_prone_fire_arms = stable_prone
					graph._configure_fire_filter(posture)
		if gun != "mark_23":
			var slots: Dictionary = driver.animation_profile.family_animation_slots.TWO_HAND_RIFLE
			check(slots["locomotion_ready/run_left"] != slots["locomotion_ready/run_right"], "left/right source takes stay distinct")
	driver.queue_free()
	await process_frame
	print("SOURCE_RIFLE_FIRE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
