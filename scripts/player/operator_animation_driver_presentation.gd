extends "res://scripts/player/operator_animation_driver_actions.gd"

## Presentation event routing and bounded fire/equipment effects.

func get_connected_route(route_name: StringName) -> Array[StringName]:
	return animation_profile.connected_route(route_name)


func resolve_presentation_event(
	event_name: StringName,
	extra_context: Dictionary = {}
) -> Dictionary:
	if presentation_router == null:
		return {}
	return presentation_router.resolve(event_name, _presentation_context(extra_context))


func present_event(
	event_name: StringName,
	extra_context: Dictionary = {}
) -> Dictionary:
	if presentation_router == null:
		return {}
	_last_event_presentation = presentation_router.present(
		event_name,
		_presentation_context(extra_context),
		Callable(self, "_apply_presentation_plan")
	)
	return _last_event_presentation.duplicate(true)


func describe_presentation_plan(plan: Dictionary) -> String:
	return presentation_router.describe(plan) if presentation_router != null else "Presentation router is not ready."


func _presentation_context(extra_context: Dictionary = {}) -> Dictionary:
	var context := extra_context.duplicate(true)
	context["posture"] = String(posture)
	context["weapon_family"] = String(equipped_weapon_family)
	context["current_base_state"] = String(_select_visual_clip())
	return context


func _apply_presentation_plan(plan: Dictionary) -> bool:
	match StringName(plan.get("event", "")):
		&"FIRE_ACCEPTED":
			return _apply_fire_presentation(plan)
		&"RELOAD_STARTED":
			var target_duration := float(
				(plan.get("context", {}) as Dictionary).get(
					"target_duration_seconds",
					weapon_reload_duration_seconds()
				)
			)
			return _play_presentation_action_timed(plan, target_duration)
		_:
			var clip_name := StringName(plan.get("state", ""))
			return play_action(
				clip_name,
				float(plan.get("blend_in_seconds", transition_blend_seconds))
			)


func _play_presentation_action_timed(plan: Dictionary, target_duration_seconds: float) -> bool:
	var clip_name := StringName(plan.get("state", ""))
	if StringName(plan.get("event", "")) == &"RELOAD_STARTED":
		# The router chooses the rifle-family action; the equipped visual contract
		# chooses the actual weapon clip. Keeping this final lookup in the canonical
		# consumer lets AK/M4 share gameplay reload authority while using different
		# authored presentation takes.
		var equipped_reload := _resolve_equipped_weapon_action(&"reload")
		if equipped_reload != &"":
			plan["family_route_state"] = String(clip_name)
			clip_name = equipped_reload
			plan["state"] = String(clip_name)
			plan["clip_path"] = String(clip_paths.get(clip_name, ""))
	if clip_name == &"" or animation_player == null:
		return false
	var animation := animation_player.get_animation(clip_name)
	if animation == null:
		return false
	var target_duration := clampf(target_duration_seconds, 0.25, 10.0)
	var playback_speed := clampf(animation.length / target_duration, 0.25, 3.0)
	return play_action(
		clip_name,
		float(plan.get("blend_in_seconds", transition_blend_seconds)),
		playback_speed
	)


func notify_fired() -> bool:
	var plan := present_event(&"FIRE_ACCEPTED")
	return bool(plan.get("applied", false))


func _apply_fire_presentation(plan: Dictionary) -> bool:
	if skeleton == null or locomotion_graph == null:
		return false
	var event_fire_clip := StringName(plan.get("state", ""))
	var presentation_effects: Array = plan.get("effects", [])
	if AnimationStateContract.ENTER_READY_AIM in presentation_effects:
		_trigger_fire_ready_aim()
	if _fire_uses_aim_idle(event_fire_clip):
		# FIRE_RECOVERY owns the stable Aim Idle presentation for its bounded
		# interval. Do not start a second combat_fire/crouch_fire one-shot here.
		_fire_pose_clip = &""
		_fire_pose_time = 0.0
		_fire_pose_duration = 0.0
		return true
	_fire_pose_clip = locomotion_graph.trigger_fire(posture, event_fire_clip)
	_fire_pose_time = 0.0
	var fire_animation := (
		animation_player.get_animation(_fire_pose_clip)
		if animation_player != null and _fire_pose_clip != &""
		else null
	)
	_fire_pose_duration = fire_animation.length if fire_animation != null else 0.0
	return true


func notify_weapon_equipped(raw_config: Dictionary) -> bool:
	return WeaponEquipmentRuntime.apply(self, raw_config)


func set_trooper_scale(new_scale: float) -> void:
	trooper_scale = new_scale
	if asset_runtime != null:
		asset_runtime.set_operator_scale(new_scale)


func set_modern_locomotion_enabled(enabled: bool) -> void:
	use_modern_locomotion = enabled
	if locomotion_graph != null:
		locomotion_graph.set_modern_enabled(enabled)
