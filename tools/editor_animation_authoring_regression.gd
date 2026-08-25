extends SceneTree

const Repository := preload("res://addons/socom_authoring/animation_route_repository.gd")
const Dock := preload("res://addons/socom_authoring/animation_routes_dock.gd")
const RuntimeProfile := preload("res://scripts/player/operator_animation_profile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_hash_before := FileAccess.get_sha256(Repository.PROFILE_PATH)
	var temporary_profile := "/private/tmp/socom-editor-animation-authoring-%d.json" % OS.get_process_id()
	_expect(_copy_text_file(Repository.PROFILE_PATH, temporary_profile), "test profile copy is isolated in temporary storage")
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
		(fire.get("effects", []) as Array).has("ENTER_READY_AIM")
		and not (fire.get("effects", []) as Array).has("RAIL_TO_BLUE_LINE"),
		"editor exposes ready aim without a live rail relocation effect"
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

	var undo_redo := UndoRedo.new()
	var transaction_handler: Callable = (
		func(action_name: String, before: Dictionary, after: Dictionary) -> void:
			undo_redo.create_action(action_name)
			undo_redo.add_do_method(dock.apply_document_snapshot.bind(after))
			undo_redo.add_undo_method(dock.apply_document_snapshot.bind(before))
			undo_redo.commit_action()
	)
	dock.document_transaction_requested.connect(transaction_handler)
	dock.configure_profile_path(temporary_profile)
	dock.select_context("FIRE_ACCEPTED", "STANDING", "TWO_HAND_RIFLE", "run_forward")
	var temporary_hash_before := FileAccess.get_sha256(temporary_profile)
	var proposal := dock.propose_rule(
		"When a valid rifle shot happens, play this on torso and arms, "
		+ "blend in 0.08, blend out 0.16, return to current movement",
		"combat_fire"
	)
	_expect(bool(proposal.get("ok", false)), "natural-language fire rule builds a validated proposal")
	_expect(not dock.repository.is_dirty(), "proposal review does not mutate the in-memory profile")
	_expect(
		FileAccess.get_sha256(temporary_profile) == temporary_hash_before,
		"proposal review never writes the profile"
	)
	_expect(dock.approve_pending_proposal(), "approved proposal enters Godot undo history")
	var edited_fire: Dictionary = dock.repository.resolve(
		"FIRE_ACCEPTED", "STANDING", "TWO_HAND_RIFLE", "run_forward"
	)
	_expect(is_equal_approx(float(edited_fire.get("blend_in_seconds", 0.0)), 0.08), "approved draft updates the live editor preview")
	_expect(dock.repository.is_dirty(), "approved draft is visibly unsaved")
	_expect(
		FileAccess.get_sha256(temporary_profile) == temporary_hash_before,
		"approved draft still does not write the profile"
	)
	undo_redo.undo()
	var undone_fire: Dictionary = dock.repository.resolve(
		"FIRE_ACCEPTED", "STANDING", "TWO_HAND_RIFLE", "run_forward"
	)
	_expect(is_equal_approx(float(undone_fire.get("blend_in_seconds", 0.0)), 0.04), "Godot undo restores the previous route")
	_expect(not dock.repository.is_dirty(), "undo restores the saved document identity")
	undo_redo.redo()
	var redone_fire: Dictionary = dock.repository.resolve(
		"FIRE_ACCEPTED", "STANDING", "TWO_HAND_RIFLE", "run_forward"
	)
	_expect(is_equal_approx(float(redone_fire.get("blend_in_seconds", 0.0)), 0.08), "Godot redo restores the approved route")
	var invalid_proposal := dock.propose_rule(
		"When a valid rifle shot happens, play this on the whole body",
		"run_forward"
	)
	_expect(not bool(invalid_proposal.get("ok", false)), "fire route rejects a locomotion clip")
	var save_result := dock.save_approved_draft()
	_expect(bool(save_result.get("ok", false)), "explicit save atomically writes the approved draft")
	_expect(not dock.repository.is_dirty(), "successful save clears the draft marker")
	_expect(
		not FileAccess.file_exists("%s.socom-writing-%d" % [temporary_profile, OS.get_process_id()]),
		"atomic save leaves no temporary writer file"
	)
	var saved_runtime_profile = RuntimeProfile.new()
	saved_runtime_profile.load_project_map(temporary_profile)
	var saved_runtime_fire := saved_runtime_profile.resolve_animation_event_presentation(
		&"FIRE_ACCEPTED", &"STANDING", &"TWO_HAND_RIFLE"
	)
	_expect(is_equal_approx(float(saved_runtime_fire.get("blend_in_seconds", 0.0)), 0.08), "saved editor route is consumed unchanged by runtime")
	_expect(_append_text(temporary_profile, "\n"), "conflict fixture changes the profile outside the dock")
	var conflict_proposal := dock.propose_rule(
		"When a valid rifle shot happens, play this on torso and arms, blend in 0.09",
		"combat_fire"
	)
	_expect(bool(conflict_proposal.get("ok", false)), "second valid proposal is available for conflict test")
	_expect(dock.approve_pending_proposal(), "second proposal becomes a draft")
	var conflict_save := dock.save_approved_draft()
	_expect(not bool(conflict_save.get("ok", false)), "save refuses to overwrite a profile changed on disk")
	dock.document_transaction_requested.disconnect(transaction_handler)
	undo_redo.clear_history()
	dock.queue_free()
	await process_frame
	DirAccess.remove_absolute(temporary_profile)

	var plugin_config := ConfigFile.new()
	_expect(
		plugin_config.load("res://addons/socom_authoring/plugin.cfg") == OK,
		"Godot recognizes the SOCOM authoring plugin manifest"
	)
	_expect(
		String(plugin_config.get_value("plugin", "script", "")) == "socom_authoring_plugin.gd",
		"plugin manifest selects the editor plugin"
	)
	var plugin_source := FileAccess.get_file_as_string(
		"res://addons/socom_authoring/socom_authoring_plugin.gd"
	)
	_expect(
		plugin_source.contains("dock.transient = true")
		and plugin_source.contains("_focus_routes_after_layout.call_deferred()"),
		"plugin ignores stale closed layouts and focuses the dock after restoration"
	)
	_expect(
		plugin_source.contains("add_tool_menu_item(TOOL_MENU_TITLE"),
		"plugin exposes a persistent Project Tools command for route-dock recovery"
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


func _copy_text_file(source_path: String, target_path: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var contents := source.get_as_text()
	source.close()
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_string(contents)
	target.close()
	return true


func _append_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_string(text)
	file.close()
	return true
