extends SceneTree

const TUNING_PATH := "res://config/operator_movement_tuning.json"
const ANIMATION_PATH := "res://config/operator_animation_map.json"

var failures: Array[String] = []

func _init() -> void:
    var tuning := _read_json(TUNING_PATH)
    var animation_map := _read_json(ANIMATION_PATH)
    _validate_tuning(tuning)
    _validate_animation_map(animation_map)
    if failures.is_empty():
        print("OPERATOR_CONFIG_VALIDATION PASS")
        quit(0)
        return
    else:
        for failure in failures:
            push_error(failure)
        print("OPERATOR_CONFIG_VALIDATION FAIL ", failures)
        quit(1)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        failures.append("missing configuration: %s" % path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
    if not (parsed is Dictionary):
        failures.append("invalid JSON object: %s" % path)
        return {}
    return parsed as Dictionary

func _validate_tuning(config: Dictionary) -> void:
    var movement: Dictionary = config.get("movement", {})
    var animation: Dictionary = config.get("animation", {})
    var adaptive: Dictionary = config.get("adaptive_intent", {})
    _range(movement, "move_speed", 1.0, 12.0)
    _range(movement, "full_gait_input_threshold", 0.25, 0.95)
    _range(movement, "crouch_speed", 0.25, 6.0)
    _range(movement, "prone_speed", 0.1, 4.0)
    _range(movement, "acceleration", 1.0, 80.0)
    _range(movement, "braking_acceleration", 1.0, 80.0)
    _range(movement, "reversal_acceleration", 1.0, 120.0)
    _range(movement, "torso_to_legs_degrees", 20.0, 70.0)
    _range(animation, "state_blend_seconds", 0.02, 0.4)
    _range(animation, "dive_trim_seconds", 0.4, 1.6)
    _range(animation, "roll_trim_seconds", 0.3, 1.4)
    _range(animation, "operator_scale", 40.0, 85.0)
    _range(adaptive, "decision_rate_hz", 0.5, 10.0)
    _range(adaptive, "maximum_intent_age_seconds", 0.1, 2.0)

func _validate_animation_map(config: Dictionary) -> void:
    var clips: Dictionary = config.get("clips", {})
    for required in [
        "idle_rifle", "aim_idle",
        "walk_forward", "walk_forward_left", "walk_left", "walk_back_left",
        "walk_backward", "walk_back_right", "walk_right", "walk_forward_right",
        "run_forward", "run_forward_left", "run_left", "run_back_left",
        "run_backward", "run_back_right", "run_right", "run_forward_right",
        "idle_crouch", "idle_prone", "prone_forward", "prone_backward",
        "jump_up", "jump_loop", "jump_down", "dive_roll", "roll",
        "start_forward", "stop_forward", "run_to_stop",
        "turn_90_left", "turn_90_right",
    ]:
        if not clips.has(required) or str(clips[required]).is_empty():
            failures.append("required animation slot is empty: %s" % required)
    for slot_name in clips.keys():
        var path := str(clips[slot_name])
        if not path.is_empty() and not ResourceLoader.exists(path):
            failures.append("animation slot %s has a missing resource: %s" % [slot_name, path])
        if "sprint" in str(slot_name).to_lower():
            failures.append("sprint is not a SOCOM locomotion slot: %s" % slot_name)
    var mirrored_clips: Dictionary = config.get("mirrored_clips", {})
    var leg_mirrored_clips: Dictionary = config.get("leg_mirrored_clips", {})
    var clip_aliases: Dictionary = config.get("clip_aliases", {})
    var symmetric_sources := {
        "walk_forward_left": "walk_forward_right",
        "walk_left": "walk_right",
        "walk_back_left": "walk_back_right",
        "run_forward_left": "run_forward_right",
        "run_back_left": "run_back_right",
        "crouch_forward_left": "crouch_forward_right",
        "crouch_left": "crouch_right",
        "crouch_back_left": "crouch_back_right",
    }
    for required_mirror in symmetric_sources:
        if (
            not mirrored_clips.has(required_mirror)
            and not leg_mirrored_clips.has(required_mirror)
            and not clip_aliases.has(required_mirror)
        ):
            var authored_source := str(symmetric_sources[required_mirror])
            if (
                not clips.has(required_mirror)
                or not clips.has(authored_source)
                or str(clips[required_mirror]) == str(clips[authored_source])
            ):
                failures.append("missing mirrored or independently authored locomotion pair: %s" % required_mirror)
            continue
        var source_name := str(
            mirrored_clips[required_mirror]
            if mirrored_clips.has(required_mirror)
            else (
                leg_mirrored_clips[required_mirror]
                if leg_mirrored_clips.has(required_mirror)
                else clip_aliases[required_mirror]
            )
        )
        if source_name == required_mirror or not clips.has(source_name):
            failures.append("invalid symmetric locomotion mirror: %s <- %s" % [required_mirror, source_name])
    if mirrored_clips.has("run_left"):
        failures.append("left tactical run must not mirror hips or upper-body tracks")
    if leg_mirrored_clips.has("run_left"):
        failures.append("left tactical run must use the approved forward-left take, not a leg mirror")
    if str(clip_aliases.get("run_left", "")) != "run_forward_left":
        failures.append("left tactical run must alias the approved run-forward-left take")
    var locomotion: Dictionary = config.get("locomotion", {})
    _range(locomotion, "walk_nominal_speed_mps", 0.5, 4.0)
    _range(locomotion, "full_nominal_speed_mps", 2.0, 9.0)
    _range(locomotion, "crouch_nominal_speed_mps", 0.5, 4.0)
    _range(locomotion, "prone_nominal_speed_mps", 0.2, 2.5)
    _range(locomotion, "speed_blend_start", 0.05, 0.8)
    _range(locomotion, "speed_blend_end", 0.3, 1.0)
    _range(locomotion, "minimum_playback_rate", 0.4, 1.0)
    _range(locomotion, "maximum_playback_rate", 1.0, 2.0)
    _range(locomotion, "direction_response", 4.0, 30.0)
    _range(locomotion, "lateral_snap_threshold", 0.75, 1.0)
    _range(locomotion, "speed_blend_response", 4.0, 30.0)
    if float(locomotion.get("speed_blend_start", 1.0)) >= float(locomotion.get("speed_blend_end", 0.0)):
        failures.append("speed_blend_start must be lower than speed_blend_end")

func _range(section: Dictionary, key: String, minimum: float, maximum: float) -> void:
    if not section.has(key):
        failures.append("missing tuning value: %s" % key)
        return
    var value := float(section[key])
    if value < minimum or value > maximum:
        failures.append("%s must be between %.2f and %.2f" % [key, minimum, maximum])
