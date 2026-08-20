class_name SocomOperatorAnimationProfile
extends RefCounted

## Single source of truth for logical animation slots and locomotion calibration.
## The gameplay controller never reads clip paths or animation timing metadata.

const MAP_PATH := "res://config/operator_animation_map.json"
const PlaytestStateCollector := preload("res://scripts/runtime/playtest_state_collector.gd")

const DIRECTION_SUFFIXES: Array[StringName] = [
	&"forward", &"forward_left", &"left", &"back_left",
	&"backward", &"back_right", &"right", &"forward_right",
]

const DEFAULT_CLIPS: Dictionary = {
	&"idle_rifle": "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx",
	&"aim_idle": "res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx",
	&"run_forward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run forward.fbx",
	&"run_backward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run backward.fbx",
	&"run_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run left.fbx",
	&"run_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run right.fbx",
	&"run_forward_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run forward left.fbx",
	&"run_forward_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run forward right.fbx",
	&"run_back_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run backward left.fbx",
	&"run_back_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run backward right.fbx",
	&"walk_forward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk forward.fbx",
	&"walk_backward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk backward.fbx",
	&"walk_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk left.fbx",
	&"walk_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk right.fbx",
	&"walk_forward_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk forward left.fbx",
	&"walk_forward_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk forward right.fbx",
	&"walk_back_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk backward left.fbx",
	&"walk_back_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk backward right.fbx",
	&"idle_crouch": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
	&"crouch_forward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward.fbx",
	&"crouch_backward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching backward.fbx",
	&"crouch_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching left.fbx",
	&"crouch_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching right.fbx",
	&"crouch_forward_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward left.fbx",
	&"crouch_forward_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward right.fbx",
	&"crouch_back_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching backward left.fbx",
	&"crouch_back_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching backward right.fbx",
	&"idle_prone": "res://assets/animations/mixamo/Prone Firing Rifle.fbx",
	&"prone_forward": "res://assets/animations/mixamo/Prone Forward.fbx",
	&"prone_backward": "res://assets/animations/mixamo/Moving Backward In Prone Position.fbx",
	&"prone_turn_left": "res://assets/animations/mixamo/Prone Left Turn.fbx",
	&"prone_turn_right": "res://assets/animations/mixamo/Prone Left Turn.fbx",
	&"prone_fire": "res://assets/animations/mixamo/Prone Firing Rifle.fbx",
	&"prone_reload": "res://assets/animations/mixamo/Prone Reloading.fbx",
	&"dive_roll": "res://assets/animations/mixamo/Running Dive Roll.fbx",
	&"roll": "res://assets/animations/mixamo/Run To Rolling.fbx",
	&"jump_up": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/jump up.fbx",
	&"jump_loop": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/jump loop.fbx",
	&"jump_down": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/jump down.fbx",
	&"combat_fire": "res://assets/animations/mixamo/Shooter Pack/firing rifle.fbx",
	&"crouch_fire": "res://assets/animations/mixamo/Crouch Rapid Fire.fbx",
	&"reload": "res://assets/animations/mixamo/Reloading.fbx",
	&"death_right": "res://assets/animations/mixamo/Pro Rifle Pack/death from right.fbx",
	&"climb": "res://assets/animations/mixamo/Climbing.fbx",
	&"crouch_to_prone": "res://assets/animations/mixamo/Rifle Kneel To Prone.fbx",
	&"crouch_to_stand": "res://assets/animations/mixamo/Crouch To Standing With Rifle.fbx",
	&"grenade_toss": "res://assets/animations/mixamo/toss grenade.fbx",
	&"grenade_throw": "res://assets/animations/mixamo/Throw Grenade.fbx",
	&"jump_forward_action": "res://assets/animations/mixamo/Shooter Pack/jump forward.fbx",
	&"jump_backward_action": "res://assets/animations/mixamo/Jump Away.fbx",
	&"prone_stop_forward": "res://assets/animations/mixamo/Prone Forward Stop.fbx",
	&"prone_stop_backward": "res://assets/animations/mixamo/Prone Backwards Stop.fbx",
	&"pistol_idle": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol idle.fbx",
	&"pistol_idle_kneeling": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol kneeling idle.fbx",
	&"pistol_walk_forward": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk.fbx",
	&"pistol_walk_backward": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk backward.fbx",
	&"pistol_strafe_left": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol strafe.fbx",
	&"pistol_strafe_right": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol strafe (2).fbx",
	&"pistol_walk_forward_left": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk arc.fbx",
	&"pistol_walk_forward_right": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk arc (2).fbx",
	&"pistol_walk_back_left": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk backward arc.fbx",
	&"pistol_walk_back_right": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk backward arc (2).fbx",
	&"pistol_run_forward": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run.fbx",
	&"pistol_run_backward": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run backward.fbx",
	&"pistol_run_forward_left": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run arc.fbx",
	&"pistol_run_forward_right": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run arc (2).fbx",
	&"pistol_run_back_left": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run backward arc.fbx",
	&"pistol_run_back_right": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run backward arc (2).fbx",
	&"pistol_jump": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol jump.fbx",
	&"pistol_jump_alt": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol jump (2).fbx",
	&"pistol_stand_to_kneel": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol stand to kneel.fbx",
	&"pistol_kneel_to_stand": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol kneel to stand.fbx",
	&"start_forward": "res://assets/animations/mixamo/Start Walking.fbx",
	&"start_backward": "res://assets/animations/mixamo/Shooter Pack/start walking backwards.fbx",
	&"stop_forward": "res://assets/animations/mixamo/Shooter Pack/stop walking.fbx",
	&"stop_backward": "res://assets/animations/mixamo/Shooter Pack/walk backwards stop.fbx",
	&"run_to_stop": "res://assets/animations/mixamo/Run To Stop.fbx",
	&"crouch_start": "res://assets/animations/mixamo/Rifle Crouch Idle To Walk.fbx",
	&"crouch_stop": "res://assets/animations/mixamo/Crouch Stop Walking.fbx",
	&"turn_90_left": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/turn 90 left.fbx",
	&"turn_90_right": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/turn 90 right.fbx",
}

const LOOPING_CLIPS: Array[StringName] = [
	&"idle_rifle", &"aim_idle",
	&"run_forward", &"run_backward", &"run_left", &"run_right",
	&"run_forward_left", &"run_forward_right", &"run_back_left", &"run_back_right",
	&"walk_forward", &"walk_backward", &"walk_left", &"walk_right",
	&"walk_forward_left", &"walk_forward_right", &"walk_back_left", &"walk_back_right",
	&"idle_crouch", &"crouch_forward", &"crouch_backward", &"crouch_left", &"crouch_right",
	&"crouch_forward_left", &"crouch_forward_right", &"crouch_back_left", &"crouch_back_right",
	&"idle_prone", &"prone_forward", &"prone_backward", &"prone_turn_left", &"prone_turn_right",
	&"jump_loop",
	&"climb",
	&"pistol_idle", &"pistol_idle_kneeling",
	&"pistol_walk_forward", &"pistol_walk_backward",
	&"pistol_strafe_left", &"pistol_strafe_right",
	&"pistol_walk_forward_left", &"pistol_walk_forward_right",
	&"pistol_walk_back_left", &"pistol_walk_back_right",
	&"pistol_run_forward", &"pistol_run_backward",
	&"pistol_run_forward_left", &"pistol_run_forward_right",
	&"pistol_run_back_left", &"pistol_run_back_right",
]

const DEFAULT_MIRRORED_CLIPS: Dictionary = {
	&"walk_forward_left": &"walk_forward_right",
	&"walk_left": &"walk_right",
	&"walk_back_left": &"walk_back_right",
	&"run_forward_left": &"run_forward_right",
	&"run_back_left": &"run_back_right",
	&"crouch_forward_left": &"crouch_forward_right",
	&"crouch_back_left": &"crouch_back_right",
}

const DEFAULT_LEG_MIRRORED_CLIPS: Dictionary = {
}

const DEFAULT_CLIP_ALIASES: Dictionary = {
	&"run_left": &"run_forward_left",
	&"run_right": &"run_forward_right",
	&"crouch_left": &"crouch_forward_left",
	&"crouch_right": &"crouch_forward_right",
}

const DEFAULT_POSE_YAW_OFFSETS_DEGREES: Dictionary = {
	&"run_left": 6.0,
	&"run_right": -6.0,
	&"crouch_left": 6.0,
	&"crouch_right": -6.0,
}

const DEFAULT_SEMANTIC_ACTIONS: Dictionary = {
	"fire": {
		"STANDING": "combat_fire",
		"CROUCHED": "crouch_fire",
		"PRONE": "prone_fire",
		"ANY": "combat_fire",
	},
	"reload": {
		"STANDING": "reload",
		"CROUCHED": "reload",
		"PRONE": "prone_reload",
		"ANY": "reload",
	},
	"grenade_quick": {"ANY": "grenade_toss"},
	"grenade_full": {"ANY": "grenade_throw"},
	"climb": {"ANY": "climb"},
	"death_right": {"ANY": "death_right"},
	"jump_forward": {"ANY": "jump_forward_action"},
	"jump_backward": {"ANY": "jump_backward_action"},
	"posture_to_prone": {"CROUCHED": "crouch_to_prone"},
	"posture_to_standing": {"CROUCHED": "crouch_to_stand"},
}

const DEFAULT_CONNECTED_ROUTES: Dictionary = {
	"standing_forward": [
		"idle_rifle", "start_forward", "walk_forward",
		"run_forward", "run_to_stop", "stop_forward", "idle_rifle",
	],
	"standing_backward": [
		"idle_rifle", "start_backward", "walk_backward",
		"run_backward", "run_to_stop", "stop_backward", "idle_rifle",
	],
	"crouch_forward": [
		"idle_crouch", "crouch_start", "crouch_forward",
		"crouch_stop", "idle_crouch",
	],
	"prone_forward": [
		"idle_prone", "prone_forward", "prone_stop_forward", "idle_prone",
	],
	"prone_backward": [
		"idle_prone", "prone_backward", "prone_stop_backward", "idle_prone",
	],
	"dive_to_prone": ["run_forward", "dive_roll", "idle_prone"],
	"roll_to_crouch": ["run_forward", "roll", "idle_crouch"],
}

var clip_paths: Dictionary = DEFAULT_CLIPS.duplicate(true)
var mirrored_clips: Dictionary = DEFAULT_MIRRORED_CLIPS.duplicate(true)
var leg_mirrored_clips: Dictionary = DEFAULT_LEG_MIRRORED_CLIPS.duplicate(true)
var clip_aliases: Dictionary = DEFAULT_CLIP_ALIASES.duplicate(true)
var pose_yaw_offsets_degrees: Dictionary = DEFAULT_POSE_YAW_OFFSETS_DEGREES.duplicate(true)
var semantic_actions: Dictionary = DEFAULT_SEMANTIC_ACTIONS.duplicate(true)
var connected_routes: Dictionary = DEFAULT_CONNECTED_ROUTES.duplicate(true)
var locomotion: Dictionary = {
	"walk_nominal_speed_mps": 2.15,
	"full_nominal_speed_mps": 5.70,
	"crouch_nominal_speed_mps": 2.60,
	"prone_nominal_speed_mps": 1.25,
	"speed_blend_start": 0.38,
	"speed_blend_end": 0.86,
	"minimum_playback_rate": 0.72,
	"maximum_playback_rate": 1.32,
	"direction_response": 16.0,
	"rendered_direction_response": 8.0,
	"direction_turn_playback_floor": 0.72,
	"lateral_snap_threshold": 0.92,
	"speed_blend_response": 12.0,
	"phase_offsets": {},
}
var transitions: Dictionary = {
	"enabled": true,
	"start_seconds": 0.18,
	"stop_seconds": 0.20,
	"reversal_seconds": 0.22,
	"planted_turn_seconds": 0.30,
	"reversal_dot_threshold": -0.55,
	"planted_turn_degrees": 34.0,
}
var warnings: Array[String] = []


func load_project_map(path: String = MAP_PATH) -> void:
	clip_paths = DEFAULT_CLIPS.duplicate(true)
	mirrored_clips = DEFAULT_MIRRORED_CLIPS.duplicate(true)
	leg_mirrored_clips = DEFAULT_LEG_MIRRORED_CLIPS.duplicate(true)
	clip_aliases = DEFAULT_CLIP_ALIASES.duplicate(true)
	pose_yaw_offsets_degrees = DEFAULT_POSE_YAW_OFFSETS_DEGREES.duplicate(true)
	semantic_actions = DEFAULT_SEMANTIC_ACTIONS.duplicate(true)
	connected_routes = DEFAULT_CONNECTED_ROUTES.duplicate(true)
	warnings.clear()
	var config := (
		PlaytestStateCollector.bundled_state("animation_map")
		if path == MAP_PATH
		else {}
	)
	if config.is_empty():
		if not FileAccess.file_exists(path):
			warnings.append("animation map missing; using built-in defaults")
			return
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if not (parsed is Dictionary):
			warnings.append("animation map is invalid JSON; using built-in defaults")
			return
		config = parsed as Dictionary
	_apply_clip_entries(config.get("clips", {}))
	_apply_mirrored_entries(config.get("mirrored_clips", DEFAULT_MIRRORED_CLIPS))
	_apply_leg_mirrored_entries(config.get("leg_mirrored_clips", DEFAULT_LEG_MIRRORED_CLIPS))
	_apply_alias_entries(config.get("clip_aliases", DEFAULT_CLIP_ALIASES))
	_apply_pose_yaw_offset_entries(config.get("pose_yaw_offsets_degrees", DEFAULT_POSE_YAW_OFFSETS_DEGREES))
	_apply_semantic_action_entries(config.get("semantic_actions", DEFAULT_SEMANTIC_ACTIONS))
	_apply_connected_route_entries(config.get("connected_routes", DEFAULT_CONNECTED_ROUTES))
	_merge_numeric_section(locomotion, config.get("locomotion", {}))
	_merge_numeric_section(transitions, config.get("transitions", {}))


func is_looping(clip_name: StringName) -> bool:
	return LOOPING_CLIPS.has(clip_name)


func nominal_speed(posture: StringName, full_gait_weight: float) -> float:
	if posture == &"CROUCHED":
		return float(locomotion["crouch_nominal_speed_mps"])
	if posture == &"PRONE":
		return float(locomotion["prone_nominal_speed_mps"])
	return lerpf(
		float(locomotion["walk_nominal_speed_mps"]),
		float(locomotion["full_nominal_speed_mps"]),
		clampf(full_gait_weight, 0.0, 1.0)
	)


func full_gait_weight(speed_normalized: float) -> float:
	return smoothstep(
		float(locomotion["speed_blend_start"]),
		float(locomotion["speed_blend_end"]),
		clampf(speed_normalized, 0.0, 1.0)
	)


func playback_rate(actual_speed_mps: float, posture: StringName, full_weight: float) -> float:
	var nominal := maxf(nominal_speed(posture, full_weight), 0.001)
	return clampf(
		actual_speed_mps / nominal,
		float(locomotion["minimum_playback_rate"]),
		float(locomotion["maximum_playback_rate"])
	)


func phase_offset(clip_name: StringName) -> float:
	var offsets: Dictionary = locomotion.get("phase_offsets", {})
	return wrapf(float(offsets.get(String(clip_name), 0.0)), 0.0, 1.0)


func mirror_source(clip_name: StringName) -> StringName:
	return StringName(mirrored_clips.get(clip_name, &""))


func leg_mirror_source(clip_name: StringName) -> StringName:
	return StringName(leg_mirrored_clips.get(clip_name, &""))


func alias_source(clip_name: StringName) -> StringName:
	return StringName(clip_aliases.get(clip_name, &""))


func pose_yaw_offset_degrees(clip_name: StringName) -> float:
	return float(pose_yaw_offsets_degrees.get(clip_name, 0.0))


func resolve_semantic_action(action_name: StringName, posture_name: StringName) -> StringName:
	var route: Variant = semantic_actions.get(String(action_name), {})
	if not (route is Dictionary):
		return &""
	var posture_key := String(posture_name).to_upper()
	var clip_name := StringName((route as Dictionary).get(posture_key, (route as Dictionary).get("ANY", "")))
	return clip_name if clip_paths.has(clip_name) else &""


func connected_route(route_name: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var route: Variant = connected_routes.get(String(route_name), [])
	if not (route is Array):
		return result
	for raw_clip_name in route:
		var clip_name := StringName(raw_clip_name)
		if clip_paths.has(clip_name):
			result.append(clip_name)
	return result


func _apply_clip_entries(data: Variant) -> void:
	if not (data is Dictionary):
		warnings.append("animation map has no clips dictionary")
		return
	for raw_name in (data as Dictionary).keys():
		var path := str((data as Dictionary)[raw_name])
		if path.is_empty():
			continue
		if ResourceLoader.exists(path):
			clip_paths[StringName(raw_name)] = path
		else:
			warnings.append("%s points to a missing resource: %s" % [raw_name, path])


func _apply_mirrored_entries(data: Variant) -> void:
	if not (data is Dictionary):
		warnings.append("mirrored_clips is not a dictionary; using built-in symmetry pairs")
		return
	mirrored_clips.clear()
	for raw_target in (data as Dictionary).keys():
		var target := StringName(raw_target)
		var source := StringName((data as Dictionary)[raw_target])
		if target == source or not clip_paths.has(target) or not clip_paths.has(source):
			warnings.append("invalid mirrored clip pair: %s <- %s" % [target, source])
			continue
		mirrored_clips[target] = source


func _apply_leg_mirrored_entries(data: Variant) -> void:
	if not (data is Dictionary):
		warnings.append("leg_mirrored_clips is not a dictionary; using built-in leg symmetry pairs")
		return
	leg_mirrored_clips.clear()
	for raw_target in (data as Dictionary).keys():
		var target := StringName(raw_target)
		var source := StringName((data as Dictionary)[raw_target])
		if target == source or not clip_paths.has(target) or not clip_paths.has(source):
			warnings.append("invalid leg-mirrored clip pair: %s <- %s" % [target, source])
			continue
		leg_mirrored_clips[target] = source


func _apply_alias_entries(data: Variant) -> void:
	if not (data is Dictionary):
		warnings.append("clip_aliases is not a dictionary; using built-in aliases")
		return
	clip_aliases.clear()
	for raw_target in (data as Dictionary).keys():
		var target := StringName(raw_target)
		var source := StringName((data as Dictionary)[raw_target])
		if target == source or not clip_paths.has(target) or not clip_paths.has(source):
			warnings.append("invalid animation alias: %s <- %s" % [target, source])
			continue
		clip_aliases[target] = source


func _apply_pose_yaw_offset_entries(data: Variant) -> void:
	if not (data is Dictionary):
		warnings.append("pose_yaw_offsets_degrees is not a dictionary; using built-in offsets")
		return
	pose_yaw_offsets_degrees.clear()
	for raw_target in (data as Dictionary).keys():
		var target := StringName(raw_target)
		if not clip_paths.has(target):
			warnings.append("pose yaw offset references an unknown clip: %s" % target)
			continue
		var value: Variant = (data as Dictionary)[raw_target]
		if not (value is float or value is int):
			warnings.append("pose yaw offset is not numeric: %s" % target)
			continue
		pose_yaw_offsets_degrees[target] = clampf(float(value), -25.0, 25.0)


func _apply_semantic_action_entries(data: Variant) -> void:
	if not (data is Dictionary):
		warnings.append("semantic_actions is not a dictionary; using built-in routes")
		return
	semantic_actions.clear()
	for raw_action_name in (data as Dictionary).keys():
		var raw_route: Variant = (data as Dictionary)[raw_action_name]
		if not (raw_route is Dictionary):
			warnings.append("semantic action route is not a dictionary: %s" % raw_action_name)
			continue
		var route: Dictionary = {}
		for raw_posture in (raw_route as Dictionary).keys():
			var clip_name := StringName((raw_route as Dictionary)[raw_posture])
			if not clip_paths.has(clip_name):
				warnings.append("semantic action %s references an unknown clip: %s" % [raw_action_name, clip_name])
				continue
			route[String(raw_posture).to_upper()] = String(clip_name)
		if not route.is_empty():
			semantic_actions[String(raw_action_name)] = route


func _apply_connected_route_entries(data: Variant) -> void:
	if not (data is Dictionary):
		warnings.append("connected_routes is not a dictionary; using built-in routes")
		return
	connected_routes.clear()
	for raw_route_name in (data as Dictionary).keys():
		var raw_route: Variant = (data as Dictionary)[raw_route_name]
		if not (raw_route is Array):
			warnings.append("connected animation route is not an array: %s" % raw_route_name)
			continue
		var route: Array[String] = []
		for raw_clip_name in raw_route:
			var clip_name := StringName(raw_clip_name)
			if not clip_paths.has(clip_name):
				warnings.append("connected route %s references an unknown clip: %s" % [raw_route_name, clip_name])
				continue
			route.append(String(clip_name))
		if not route.is_empty():
			connected_routes[String(raw_route_name)] = route


func _merge_numeric_section(target: Dictionary, data: Variant) -> void:
	if not (data is Dictionary):
		return
	for key in (data as Dictionary).keys():
		var value: Variant = (data as Dictionary)[key]
		if key == "phase_offsets" and value is Dictionary:
			target[key] = (value as Dictionary).duplicate(true)
		elif target.has(key) and (value is float or value is int or value is bool):
			target[key] = value
