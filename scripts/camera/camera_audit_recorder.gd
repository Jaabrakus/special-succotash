class_name SocomCameraAuditRecorder
extends Node

const AUDIT_DIRECTORY := "user://camera_audits"

var camera_rig
var player
var recording: bool = false
var replaying: bool = false
var frames: Array[Dictionary] = []
var last_report_path := ""

var _file: FileAccess
var _replay_index: int = 0
var _last_camera_position := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _last_acceleration := Vector3.ZERO
var _last_state := ""
var _state_before_previous_transition := ""
var _last_transition_frame: int = -1000
var _transition_count: int = 0
var _flip_count: int = 0
var _max_step: float = 0.0
var _max_speed: float = 0.0
var _max_acceleration: float = 0.0
var _max_jerk: float = 0.0
var _status := "Audit idle"


func _ready() -> void:
    process_physics_priority = 100


func configure(new_camera_rig, new_player) -> void:
    camera_rig = new_camera_rig
    player = new_player


func start_recording() -> void:
    if camera_rig == null or player == null:
        return
    stop_replay()
    frames.clear()
    _replay_index = 0
    _last_camera_position = camera_rig.global_position
    _last_velocity = Vector3.ZERO
    _last_acceleration = Vector3.ZERO
    _last_state = camera_rig.get_camera_state_name()
    _state_before_previous_transition = ""
    _last_transition_frame = -1000
    _transition_count = 0
    _flip_count = 0
    _max_step = 0.0
    _max_speed = 0.0
    _max_acceleration = 0.0
    _max_jerk = 0.0

    DirAccess.make_dir_recursive_absolute(
        ProjectSettings.globalize_path(AUDIT_DIRECTORY)
    )
    var stamp := Time.get_datetime_string_from_system().replace(":", "-")
    last_report_path = "%s/camera_audit_%s.csv" % [AUDIT_DIRECTORY, stamp]
    _file = FileAccess.open(last_report_path, FileAccess.WRITE)
    if _file:
        _file.store_csv_line(PackedStringArray([
            "frame", "seconds", "state", "player_x", "player_y", "player_z",
            "yaw_deg", "pitch_deg", "camera_x", "camera_y", "camera_z",
            "head_x", "head_y", "reticle_x", "reticle_y", "collision",
            "step_m", "speed_mps", "acceleration_mps2", "jerk_mps3"
        ]))
    recording = true
    _status = "RECORDING — F9 to stop"


func stop_recording() -> void:
    if not recording:
        return
    recording = false
    if _file:
        _file.flush()
        _file = null
    _status = (
        "Saved %d frames | step %.3f m | accel %.1f | jerk %.1f | transitions %d | flips %d"
        % [
            frames.size(), _max_step, _max_acceleration, _max_jerk,
            _transition_count, _flip_count
        ]
    )


func toggle_recording() -> void:
    if recording:
        stop_recording()
    else:
        start_recording()


func start_replay() -> void:
    if frames.is_empty() or camera_rig == null or player == null:
        _status = "No in-memory audit to replay yet"
        return
    stop_recording()
    replaying = true
    _replay_index = 0
    player.replay_override_active = true
    camera_rig.orbit_input_enabled = false
    _status = "REPLAYING %d captured frames" % frames.size()


func stop_replay() -> void:
    replaying = false
    if player:
        player.replay_override_active = false
    if camera_rig:
        camera_rig.orbit_input_enabled = true


func _physics_process(delta: float) -> void:
    if replaying:
        _apply_replay_frame()
        return
    if recording:
        _capture_frame(delta)


func _capture_frame(delta: float) -> void:
    var data: Dictionary = camera_rig.get_debug_data()
    var camera_position: Vector3 = camera_rig.global_position
    var first_sample := frames.is_empty()
    var step: float = (
        0.0
        if first_sample
        else camera_position.distance_to(_last_camera_position)
    )
    var velocity: Vector3 = (
        Vector3.ZERO
        if first_sample
        else (camera_position - _last_camera_position) / maxf(delta, 0.0001)
    )
    var acceleration: Vector3 = (
        Vector3.ZERO
        if first_sample
        else (velocity - _last_velocity) / maxf(delta, 0.0001)
    )
    var jerk: Vector3 = (
        Vector3.ZERO
        if first_sample
        else (acceleration - _last_acceleration) / maxf(delta, 0.0001)
    )
    var state: String = str(data.camera_state)
    if state != _last_state:
        _transition_count += 1
        if (
            state == _state_before_previous_transition
            and frames.size() - _last_transition_frame <= 15
        ):
            _flip_count += 1
        _state_before_previous_transition = _last_state
        _last_transition_frame = frames.size()

    _max_step = maxf(_max_step, step)
    _max_speed = maxf(_max_speed, velocity.length())
    _max_acceleration = maxf(_max_acceleration, acceleration.length())
    _max_jerk = maxf(_max_jerk, jerk.length())

    var snapshot := {
        "player_position": player.global_position,
        "player_rotation_y": player.global_rotation.y,
        "yaw": camera_rig.yaw,
        "pitch": camera_rig.pitch,
        "aim_yaw": camera_rig.aim_yaw,
        "aim_pitch": camera_rig.aim_pitch,
        "mouse_aim_string_enabled": camera_rig.mouse_aim_string_enabled,
        "mouse_intent_yaw": camera_rig.mouse_intent_yaw,
        "mouse_intent_pitch": camera_rig.mouse_intent_pitch,
        "mouse_target_deflection": camera_rig.mouse_aim_model.target_deflection,
        "mouse_follower_deflection": camera_rig.mouse_aim_model.follower_deflection,
        "mouse_cursor_cage_enabled": camera_rig.mouse_cursor_cage_enabled,
        "mouse_cursor_deflection": camera_rig.mouse_cursor_deflection,
        "state": state
    }
    frames.append(snapshot)

    if _file:
        _file.store_csv_line(PackedStringArray([
            str(Engine.get_physics_frames()), "%.6f" % (frames.size() * delta), state,
            "%.6f" % player.global_position.x, "%.6f" % player.global_position.y,
            "%.6f" % player.global_position.z, "%.4f" % data.yaw_deg,
            "%.4f" % data.pitch_deg, "%.6f" % camera_position.x,
            "%.6f" % camera_position.y, "%.6f" % camera_position.z,
            "%.6f" % data.head_x, "%.6f" % data.head_y,
            "%.6f" % data.reticle_x, "%.6f" % data.reticle_y,
            str(data.collision), "%.6f" % step, "%.6f" % velocity.length(),
            "%.6f" % acceleration.length(), "%.6f" % jerk.length()
        ]))

    _last_state = state
    _last_camera_position = camera_position
    _last_velocity = velocity
    _last_acceleration = acceleration


func _apply_replay_frame() -> void:
    if _replay_index >= frames.size():
        stop_replay()
        _status = "Replay complete — result can be recorded again"
        return
    var snapshot: Dictionary = frames[_replay_index]
    player.global_position = snapshot.player_position
    player.global_rotation.y = float(snapshot.player_rotation_y)
    player.velocity = Vector3.ZERO
    camera_rig.yaw = float(snapshot.yaw)
    camera_rig.pitch = float(snapshot.pitch)
    camera_rig.aim_yaw = float(snapshot.get("aim_yaw", snapshot.yaw))
    camera_rig.aim_pitch = float(snapshot.get("aim_pitch", snapshot.pitch))
    camera_rig.mouse_aim_string_enabled = bool(
        snapshot.get("mouse_aim_string_enabled", false)
    )
    camera_rig.mouse_intent_yaw = float(
        snapshot.get("mouse_intent_yaw", camera_rig.aim_yaw)
    )
    camera_rig.mouse_intent_pitch = float(
        snapshot.get("mouse_intent_pitch", camera_rig.aim_pitch)
    )
    camera_rig.mouse_aim_model.target_deflection = snapshot.get(
        "mouse_target_deflection",
        Vector2.ZERO
    )
    camera_rig.mouse_aim_model.follower_deflection = snapshot.get(
        "mouse_follower_deflection",
        Vector2.ZERO
    )
    camera_rig.mouse_cursor_cage_enabled = bool(
        snapshot.get("mouse_cursor_cage_enabled", false)
    )
    camera_rig.mouse_cursor_deflection = snapshot.get(
        "mouse_cursor_deflection",
        Vector2.ZERO
    )
    camera_rig._update_reticle_position(0.0)
    _replay_index += 1


func get_status() -> String:
    return _status


func get_report_directory() -> String:
    return ProjectSettings.globalize_path(AUDIT_DIRECTORY)
