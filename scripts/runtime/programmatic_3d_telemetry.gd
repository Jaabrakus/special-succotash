class_name SocomProgrammatic3DTelemetry
extends Node

## Streams a bounded, read-only 3D description of the live game. This node may
## observe transforms and presentation state, but never writes gameplay state.

signal recording_changed(recording: bool, path: String)

const PROFILE_PATH := "res://config/programmatic_3d_telemetry.json"
const OUTPUT_DIRECTORY := "user://programmatic_3d"
const LATEST_SNAPSHOT_PATH := OUTPUT_DIRECTORY + "/latest_snapshot.json"
const DEFAULT_BONES: Array[StringName] = [
	&"mixamorig_Hips", &"mixamorig_Spine", &"mixamorig_Spine1",
	&"mixamorig_Spine2", &"mixamorig_Head",
	&"mixamorig_LeftShoulder", &"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
	&"mixamorig_RightShoulder", &"mixamorig_RightArm",
	&"mixamorig_RightForeArm", &"mixamorig_RightHand", &"ik_hand_gun",
]
const DEFAULT_SOCKETS: Array[StringName] = [
	&"Socket_RightHand", &"Socket_LeftHand", &"Socket_BarrelBase",
	&"Socket_Muzzle", &"Socket_Buttstock", &"Socket_Optic", &"Socket_Ejection",
]

var host: Node
var profile: Dictionary = {}
var recording: bool = false
var sample_rate_hz: float = 15.0
var latest_snapshot_rate_hz: float = 10.0
var maximum_samples_per_session: int = 9000
var retained_session_files: int = 3
var flush_interval_samples: int = 15
var bone_names: Array[StringName] = DEFAULT_BONES.duplicate()
var socket_names: Array[StringName] = DEFAULT_SOCKETS.duplicate()
var session_path: String = ""
var sample_count: int = 0
var last_snapshot: Dictionary = {}
var _session_file: FileAccess
var _sample_accumulator: float = 0.0
var _latest_accumulator: float = 0.0
var _session_started_unix: float = 0.0
var _lines_since_flush: int = 0
var _status_layer: CanvasLayer
var _status_label: Label


func configure(main_host: Node) -> void:
	host = main_host
	_load_profile()
	_build_status_overlay()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_cmdline_user_args().has("--3d-telemetry"):
		call_deferred("start_recording", "command_line")


func _process(delta: float) -> void:
	if not recording:
		return
	_sample_accumulator += maxf(delta, 0.0)
	_latest_accumulator += maxf(delta, 0.0)
	var interval := 1.0 / maxf(sample_rate_hz, 1.0)
	if _sample_accumulator < interval:
		return
	_sample_accumulator = fmod(_sample_accumulator, interval)
	capture_now(true)


func _unhandled_input(event: InputEvent) -> void:
	# Public/restricted play intentionally omits developer-only input actions, but
	# this read-only observer may still be present. Never query an absent action:
	# Godot reports an error for every input event, which can become visible lag.
	if (
		InputMap.has_action("toggle_3d_telemetry")
		and event.is_action_pressed("toggle_3d_telemetry")
	):
		toggle_recording()
		get_viewport().set_input_as_handled()


func start_recording(reason: String = "manual") -> bool:
	if recording:
		return true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	_rotate_session_files()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	session_path = "%s/telemetry_%s.jsonl" % [OUTPUT_DIRECTORY, stamp]
	_session_file = FileAccess.open(session_path, FileAccess.WRITE)
	if _session_file == null:
		push_error("Programmatic 3D telemetry could not open %s" % session_path)
		session_path = ""
		return false
	recording = true
	sample_count = 0
	_sample_accumulator = 0.0
	_latest_accumulator = 0.0
	_lines_since_flush = 0
	_session_started_unix = Time.get_unix_time_from_system()
	_store_line({
		"record_type": "session",
		"schema": "socom.programmatic_3d.v1",
		"reason": reason,
		"started_unix": _session_started_unix,
		"sample_rate_hz": sample_rate_hz,
		"coordinate_system": "Godot right-handed, +Y up, -Z forward",
		"units": "meters",
	})
	_session_file.flush()
	_lines_since_flush = 0
	print("PROGRAMMATIC_3D_TELEMETRY START %s" % ProjectSettings.globalize_path(session_path))
	_update_status_overlay()
	recording_changed.emit(true, session_path)
	return true


func stop_recording(reason: String = "manual") -> void:
	if not recording:
		return
	_store_line({
		"record_type": "session_end",
		"reason": reason,
		"sample_count": sample_count,
		"ended_unix": Time.get_unix_time_from_system(),
	})
	recording = false
	if _session_file != null:
		_session_file.flush()
		_session_file.close()
	_session_file = null
	print("PROGRAMMATIC_3D_TELEMETRY STOP samples=%d" % sample_count)
	_update_status_overlay()
	recording_changed.emit(false, session_path)


func toggle_recording() -> void:
	if recording:
		stop_recording("toggle")
	else:
		start_recording("toggle")


func capture_now(write_to_session: bool = false) -> Dictionary:
	last_snapshot = _build_snapshot()
	if write_to_session and recording:
		_store_line(last_snapshot)
		sample_count += 1
		_update_status_overlay()
		if sample_count >= maximum_samples_per_session:
			stop_recording("sample_cap")
	var latest_interval := 1.0 / maxf(latest_snapshot_rate_hz, 1.0)
	if _latest_accumulator >= latest_interval or not FileAccess.file_exists(LATEST_SNAPSHOT_PATH):
		_latest_accumulator = 0.0
		_write_latest_snapshot()
	return last_snapshot.duplicate(true)


func get_last_snapshot() -> Dictionary:
	return last_snapshot.duplicate(true)


func get_status() -> String:
	return "recording • %d samples" % sample_count if recording else "idle"


func get_output_directory() -> String:
	return ProjectSettings.globalize_path(OUTPUT_DIRECTORY)


func get_latest_snapshot_path() -> String:
	return ProjectSettings.globalize_path(LATEST_SNAPSHOT_PATH)


func get_session_path() -> String:
	return ProjectSettings.globalize_path(session_path) if not session_path.is_empty() else ""


func _build_snapshot() -> Dictionary:
	var frame := Engine.get_process_frames()
	var snapshot := {
		"record_type": "frame",
		"schema": "socom.programmatic_3d.v1",
		"sequence": sample_count,
		"engine_frame": frame,
		"captured_unix": Time.get_unix_time_from_system(),
		"elapsed_seconds": (
			Time.get_unix_time_from_system() - _session_started_unix
			if _session_started_unix > 0.0
			else 0.0
		),
		"units": "meters",
		"coordinate_system": "Godot right-handed, +Y up, -Z forward",
	}
	var player := _player()
	var camera_rig := _camera_rig()
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver := mannequin.get_node_or_null("ProductionAnimation") if mannequin != null else null
	var skeleton := driver.get("skeleton") as Skeleton3D if driver != null else null
	snapshot["camera"] = _camera_snapshot(camera_rig)
	snapshot["player"] = _player_snapshot(player)
	snapshot["skeleton"] = _skeleton_snapshot(skeleton)
	snapshot["weapon"] = _weapon_snapshot(mannequin, driver, skeleton, camera_rig)
	snapshot["animation"] = _animation_snapshot(driver)
	snapshot["reload"] = _reload_snapshot(driver)
	return snapshot


func _camera_snapshot(camera_rig: Node) -> Dictionary:
	if camera_rig == null:
		return {"valid": false}
	var camera := camera_rig.get("camera") as Camera3D
	return {
		"valid": camera != null,
		"transform": _transform_map(camera.global_transform) if camera != null else {},
		"fov_degrees": camera.fov if camera != null else 0.0,
		"aim_yaw_degrees": rad_to_deg(float(camera_rig.get("aim_yaw"))),
		"aim_pitch_degrees": rad_to_deg(float(camera_rig.get("aim_pitch"))),
		"weapon_aim_point": _vector_map(Vector3(camera_rig.get("weapon_aim_point"))),
		"state": String(camera_rig.call("get_camera_state_name")) if camera_rig.has_method("get_camera_state_name") else "",
	}


func _player_snapshot(player: CharacterBody3D) -> Dictionary:
	if player == null:
		return {"valid": false}
	return {
		"valid": true,
		"transform": _transform_map(player.global_transform),
		"velocity": _vector_map(player.velocity),
		"posture": String(player.call("get_posture_name")) if player.has_method("get_posture_name") else "",
		"motion_state": String(player.call("get_motion_state_name")) if player.has_method("get_motion_state_name") else "",
		"aim_relative_yaw_degrees": rad_to_deg(float(player.call("get_aim_relative_yaw"))) if player.has_method("get_aim_relative_yaw") else 0.0,
	}


func _skeleton_snapshot(skeleton: Skeleton3D) -> Dictionary:
	if skeleton == null:
		return {"valid": false, "bones": {}}
	skeleton.force_update_all_bone_transforms()
	var bones: Dictionary = {}
	for bone_name in bone_names:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		bones[String(bone_name)] = _transform_map(
			skeleton.global_transform * skeleton.get_bone_global_pose(index)
		)
	return {
		"valid": true,
		"bone_count": skeleton.get_bone_count(),
		"captured_bone_count": bones.size(),
		"bones": bones,
	}


func _weapon_snapshot(
	mannequin: Node,
	driver: Node,
	skeleton: Skeleton3D,
	camera_rig: Node
) -> Dictionary:
	var weapon_node := driver.get("weapon_node") as Node3D if driver != null else null
	var sockets: Dictionary = {}
	if mannequin != null and mannequin.has_method("get_active_weapon_socket"):
		for socket_name in socket_names:
			var socket := mannequin.call("get_active_weapon_socket", socket_name) as Node3D
			if socket != null:
				sockets[String(socket_name)] = _transform_map(socket.global_transform)
	var barrel_direction := Vector3.ZERO
	var muzzle_position := Vector3.ZERO
	if mannequin != null and mannequin.has_method("get_active_barrel_direction"):
		barrel_direction = Vector3(mannequin.call("get_active_barrel_direction"))
		muzzle_position = Vector3(mannequin.call("get_active_muzzle_position"))
	var aim_point := Vector3(camera_rig.get("weapon_aim_point")) if camera_rig != null else Vector3.ZERO
	var aim_error := -1.0
	if barrel_direction.length_squared() > 0.99 and muzzle_position.distance_squared_to(aim_point) > 0.0001:
		aim_error = rad_to_deg(barrel_direction.angle_to(muzzle_position.direction_to(aim_point)))
	var right_hand := _bone_world_position(skeleton, &"mixamorig_RightHand")
	var left_hand := _bone_world_position(skeleton, &"mixamorig_LeftHand")
	var right_socket := _socket_position(sockets, "Socket_RightHand")
	var left_socket := _socket_position(sockets, "Socket_LeftHand")
	return {
		"valid": weapon_node != null,
		"transform": _transform_map(weapon_node.global_transform) if weapon_node != null else {},
		"sockets": sockets,
		"muzzle_position": _vector_map(muzzle_position),
		"barrel_direction": _vector_map(barrel_direction),
		"camera_convergence_error_degrees": aim_error,
		"right_hand_to_grip_meters": right_hand.distance_to(right_socket) if right_socket != Vector3.ZERO else -1.0,
		"left_hand_to_grip_meters": left_hand.distance_to(left_socket) if left_socket != Vector3.ZERO else -1.0,
	}


func _animation_snapshot(driver: Node) -> Dictionary:
	if driver == null:
		return {"valid": false}
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var weapon_pose: Dictionary = debug.get("weapon_pose", {})
	return {
		"valid": true,
		"logical_clip": String(debug.get("logical_clip", "")),
		"source_take": String(debug.get("source_take", "")),
		"movement_state": String(debug.get("gameplay_state", "")),
		"presentation_posture": String(debug.get("presentation_posture", "")),
		"weapon_ready_weight": float(debug.get("weapon_ready_weight", 0.0)),
		"presentation_ready_weight": float(debug.get("presentation_ready_weight", 0.0)),
		"weapon_owner": String(weapon_pose.get("weapon_owner", "")),
		"authored_animation_owns_weapon_mount": bool(weapon_pose.get("authored_animation_owns_weapon_mount", false)),
		"aim_sweep": (debug.get("authored_rifle_aim_sweep", {}) as Dictionary).duplicate(true),
	}


func _reload_snapshot(driver: Node) -> Dictionary:
	if driver == null:
		return {"valid": false}
	var runtime = driver.get("asset_runtime")
	var magazine := runtime.get("reload_magazine_visual") as Node3D if runtime != null else null
	return {
		"valid": true,
		"requested_action": String(driver.get("requested_action")),
		"visual_slot": String(driver.get("_active_reload_visual_slot")),
		"visual_clip": String(driver.get("_active_reload_visual_clip")),
		"visual_time_seconds": float(driver.get("_reload_visual_time")),
		"support_regrip": bool(driver.get("_reload_support_regrip")),
		"magazine_visible": magazine != null and magazine.visible,
		"magazine_transform": _transform_map(magazine.global_transform) if magazine != null else {},
	}


func _load_profile() -> void:
	profile = {}
	if FileAccess.file_exists(PROFILE_PATH):
		var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if parsed is Dictionary:
			profile = (parsed as Dictionary).duplicate(true)
	sample_rate_hz = clampf(float(profile.get("sample_rate_hz", 15.0)), 1.0, 60.0)
	latest_snapshot_rate_hz = clampf(float(profile.get("latest_snapshot_rate_hz", 10.0)), 1.0, 30.0)
	maximum_samples_per_session = clampi(int(profile.get("maximum_samples_per_session", 9000)), 60, 100000)
	retained_session_files = clampi(int(profile.get("retained_session_files", 3)), 1, 20)
	flush_interval_samples = clampi(int(profile.get("flush_interval_samples", 15)), 1, 600)
	bone_names = _string_name_array(profile.get("bones", []), DEFAULT_BONES)
	socket_names = _string_name_array(profile.get("weapon_sockets", []), DEFAULT_SOCKETS)


func _build_status_overlay() -> void:
	if _status_layer != null:
		return
	_status_layer = CanvasLayer.new()
	_status_layer.name = "Programmatic3DStatusLayer"
	_status_layer.layer = 90
	add_child(_status_layer)
	_status_label = Label.new()
	_status_label.name = "Programmatic3DStatus"
	_status_label.position = Vector2(16.0, 16.0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.24, 1.0))
	_status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_status_label.add_theme_constant_override("shadow_offset_x", 2)
	_status_label.add_theme_constant_override("shadow_offset_y", 2)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_layer.add_child(_status_label)
	_update_status_overlay()


func _update_status_overlay() -> void:
	if _status_label == null:
		return
	_status_label.visible = recording
	_status_label.text = "● 3D TELEMETRY REC  %d  [F11 stop]" % sample_count


func _write_latest_snapshot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	var file := FileAccess.open(LATEST_SNAPSHOT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(last_snapshot, "  "))
		file.close()


func _store_line(value: Dictionary) -> void:
	if _session_file == null:
		return
	_session_file.store_line(JSON.stringify(value))
	_lines_since_flush += 1
	if _lines_since_flush >= flush_interval_samples:
		_session_file.flush()
		_lines_since_flush = 0


func _rotate_session_files() -> void:
	var directory := DirAccess.open(OUTPUT_DIRECTORY)
	if directory == null:
		return
	var files: Array[String] = []
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.begins_with("telemetry_") and filename.ends_with(".jsonl"):
			files.append(filename)
		filename = directory.get_next()
	directory.list_dir_end()
	files.sort()
	while files.size() >= retained_session_files:
		var oldest: String = files.pop_front()
		directory.remove(oldest)


func _player() -> CharacterBody3D:
	return host.get("player") as CharacterBody3D if host != null else null


func _camera_rig() -> Node:
	return host.get("camera_rig") as Node if host != null else null


func _bone_world_position(skeleton: Skeleton3D, bone_name: StringName) -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var index := skeleton.find_bone(bone_name)
	return (
		(skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin
		if index >= 0
		else Vector3.ZERO
	)


func _socket_position(sockets: Dictionary, socket_name: String) -> Vector3:
	var socket: Variant = sockets.get(socket_name, {})
	if not socket is Dictionary:
		return Vector3.ZERO
	var origin: Variant = (socket as Dictionary).get("origin", {})
	return _map_vector(origin)


static func _transform_map(value: Transform3D) -> Dictionary:
	var rotation := value.basis.orthonormalized().get_euler()
	return {
		"origin": _vector_map(value.origin),
		"rotation_degrees": _vector_map(Vector3(
			rad_to_deg(rotation.x), rad_to_deg(rotation.y), rad_to_deg(rotation.z)
		)),
		"basis_x": _vector_map(value.basis.x),
		"basis_y": _vector_map(value.basis.y),
		"basis_z": _vector_map(value.basis.z),
	}


static func _vector_map(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func _map_vector(value: Variant) -> Vector3:
	if not value is Dictionary:
		return Vector3.ZERO
	var map := value as Dictionary
	return Vector3(float(map.get("x", 0.0)), float(map.get("y", 0.0)), float(map.get("z", 0.0)))


static func _string_name_array(raw: Variant, fallback: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	if raw is Array:
		for value in raw as Array:
			result.append(StringName(value))
	return result if not result.is_empty() else fallback.duplicate()
