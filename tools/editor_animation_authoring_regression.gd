extends SceneTree

const Repository := preload("res://addons/socom_authoring/animation_route_repository.gd")
const Dock := preload("res://addons/socom_authoring/animation_routes_dock.gd")
const RuntimeProfile := preload("res://scripts/player/operator_animation_profile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_hash_before := FileAccess.get_sha256(Repository.PROFILE_PATH)
	var repository = Repository.new()
	_expect(repository.load_profile(), "editor repository loads the saved animation map")
	var validation := repository.validation_snapshot()
	_expect(bool(validation.get("ok", false)), "saved animation map validates in the editor adapter")
	_expect(int(validation.get("clip_count", 0)) > 50, "editor dock sees the complete clip library")
	_expect(int(validation.get("route_count", 0)) >= 3, "editor dock sees the connected runtime events")

	var previous_bundle_setting: Variant = ProjectSettings.get_setting(
		"socom/playtest/use_active_bundle",
		false
	)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var runtime_profile = RuntimeProfile.new()
	runtime_profile.load_project_map()
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", previous_bundle_setting)
	for event_name: String in repository.event_names():
		for posture: String in ["STANDING", "CROUCHED", "PRONE"]:
			for family: String in ["", "TWO_HAND_RIFLE"]:
				var editor_plan := repository.resolve(event_name, posture, family, "idle_rifle")
				var runtime_plan := runtime_profile.resolve_animation_event_presentation(
					StringName(event_name),
					StringName(posture),
					StringName(family)
				)
				_expect(
					bool(editor_plan.get("valid", false)) == bool(runtime_plan.get("valid", false)),
					"%s %s %s connection matches runtime" % [event_name, posture, family]
				)
				if bool(editor_plan.get("valid", false)):
					for field: String in [
						"state", "clip_path", "layer", "blend_in_seconds",
						"blend_out_seconds", "return_policy", "effects",
					]:
						_expect(
							editor_plan.get(field) == runtime_plan.get(field),
							"%s %s %s shares runtime %s" % [event_name, posture, family, field]
						)

	var fire := repository.resolve("FIRE_ACCEPTED", "STANDING", "TWO_HAND_RIFLE", "run_forward")
	_expect(String(fire.get("state", "")) == "combat_fire", "standing fire resolves to combat_fire")
	_expect(String(fire.get("layer", "")) == "UPPER_BODY", "standing fire remains an upper-body overlay")
	_expect(String(fire.get("resolved_return_state", "")) == "run_forward", "fire returns to current movement")
	_expect(
		(fire.get("effects", []) as Array).has("RAIL_TO_BLUE_LINE"),
		"editor exposes the saved rail-to-blue-line effect"
	)

	var dock = Dock.new()
	root.add_child(dock)
	await process_frame
	await process_frame
	dock.select_context("RELOAD_STARTED", "PRONE", "TWO_HAND_RIFLE", "prone_forward")
	var dock_snapshot := dock.get_debug_snapshot()
	var dock_plan: Dictionary = dock_snapshot.get("plan", {})
	_expect(String(dock_plan.get("state", "")) == "prone_reload", "dock updates through explicit context controls")
	_expect(String(dock_plan.get("resolved_return_state", "")) == "prone_forward", "dock displays contextual return")
	_expect(String(dock_snapshot.get("state_text", "")).contains("prone_reload"), "dock gives a visible state cue")
	_expect(String(dock_snapshot.get("return_text", "")).contains("prone_forward"), "dock gives a visible return cue")
	var play_requests := {"count": 0}
	dock.play_requested.connect(
		func() -> void: play_requests["count"] = int(play_requests["count"]) + 1
	)
	dock.play_button.pressed.emit()
	_expect(int(play_requests["count"]) == 1, "canonical play button emits one editor-owned request")
	dock.refresh_profile()
	_expect(
		FileAccess.get_sha256(Repository.PROFILE_PATH) == source_hash_before,
		"read-only dock never rewrites the animation map"
	)
	dock.queue_free()

	var plugin_config := ConfigFile.new()
	_expect(
		plugin_config.load("res://addons/socom_authoring/plugin.cfg") == OK,
		"Godot recognizes the SOCOM authoring plugin manifest"
	)
	_expect(
		String(plugin_config.get_value("plugin", "script", "")) == "socom_authoring_plugin.gd",
		"plugin manifest selects the editor plugin"
	)
	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled",
		PackedStringArray()
	)
	_expect(
		enabled_plugins.has("res://addons/socom_authoring/plugin.cfg"),
		"project enables the SOCOM authoring dock"
	)

	if failures.is_empty():
		print("EDITOR_ANIMATION_AUTHORING_REGRESSION PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("EDITOR_ANIMATION_AUTHORING_CHECK FAIL %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("EDITOR_ANIMATION_AUTHORING_CHECK PASS %s" % message)
	else:
		failures.append(message)
