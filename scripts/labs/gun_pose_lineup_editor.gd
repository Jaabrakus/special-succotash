@tool
class_name SocomGunPoseLineupEditor
extends Node3D

## Native Godot-editor comparison scene for the canonical SOCOM operator.
##
## Every child under PoseLineup is a real scene node containing the same saved
## operator rig, TargetPivot graph, Skeleton3D modifiers, weapon scene, and a
## continuously evaluated AnimationPlayer. This scene never enters main.tscn.

const ANIMATION_MAP_PATH := "res://config/operator_animation_map.json"
const READY_CONTEXTS := [&"combat_ready", &"combat_fire"]

@export_range(0.0, 2.0, 0.05) var playback_speed := 1.0
@export_range(0.2, 2.5, 0.05) var weapon_scale := 1.0:
	set(value):
		weapon_scale = value
		_sync_weapon_scale()
@export var show_target_handles := true:
	set(value):
		show_target_handles = value
		_sync_target_visibility()
@export var apply_ik_to_all_poses := true:
	set(value):
		apply_ik_to_all_poses = value
		_sync_modifier_influences()
@export_range(-45.0, 45.0, 1.0) var aim_pitch_deg := 0.0
@export_range(-70.0, 70.0, 1.0) var aim_yaw_deg := 0.0
@export var dynamic_aim_sweep := false
const WEAPON_OPTIONS := [
	{"name": "M16A2 Rifle", "path": "res://scenes/weapons/m16a2.tscn"},
	{"name": "M4A1 Carbine", "path": "res://scenes/weapons/m4a1.tscn"},
	{"name": "AK-47 Assault Rifle", "path": "res://scenes/weapons/ak47.tscn"},
	{"name": "MP5 Submachine Gun", "path": "res://scenes/weapons/mp5.tscn"},
	{"name": "Assault Rifle 1", "path": "res://scenes/weapons/assaultrifle_1.tscn"},
	{"name": "Shotgun 1", "path": "res://scenes/weapons/shotgun_1.tscn"},
	{"name": "Sniper Rifle 1", "path": "res://scenes/weapons/sniperrifle_1.tscn"},
	{"name": "Pistol 1", "path": "res://scenes/weapons/pistol_1.tscn"},
]

var _clip_paths: Dictionary = {}
var _entries: Array[Dictionary] = []
var _initialized := false
var _status := "Not initialized"
var _runtime_camera: Camera3D
var _runtime_camera_target := Vector3(0.0, 1.0, 0.0)
var _runtime_camera_distance := 17.0
var _runtime_camera_yaw := PI
var _runtime_camera_pitch := 0.16
var _runtime_orbiting := false
var _runtime_panning := false
var _runtime_last_pointer := Vector2.ZERO
var _focused_pose_index := -1
var _runtime_ui_layer: CanvasLayer
var _scale_value_label: Label
var _pitch_value_label: Label
var _yaw_value_label: Label


func _ready() -> void:
	set_process(true)
	if not Engine.is_editor_hint():
		_runtime_camera = get_node_or_null("RuntimeReviewCamera") as Camera3D
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sync_runtime_camera()
		_build_runtime_side_editor()
	call_deferred("reload_lineup")


func _process(delta: float) -> void:
	if not _initialized:
		return
	for entry: Dictionary in _entries:
		var player := entry.get("player") as AnimationPlayer
		if player != null and player.is_playing():
			player.advance(delta * playback_speed)
		_update_entry_aim(entry)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _runtime_camera == null:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE or mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			if Input.is_key_pressed(KEY_SHIFT):
				_runtime_panning = mouse_button.pressed
				_runtime_orbiting = false
			else:
				_runtime_orbiting = mouse_button.pressed
				_runtime_panning = false
			_runtime_last_pointer = mouse_button.position
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_runtime_camera_distance = maxf(1.0, _runtime_camera_distance - 0.75)
			_sync_runtime_camera()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_runtime_camera_distance = minf(35.0, _runtime_camera_distance + 0.75)
			_sync_runtime_camera()
	elif event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		var pointer_delta := mouse_motion.position - _runtime_last_pointer
		_runtime_last_pointer = mouse_motion.position
		if _runtime_panning:
			var right_dir := _runtime_camera.global_transform.basis.x
			var up_dir := _runtime_camera.global_transform.basis.y
			_runtime_camera_target -= (right_dir * pointer_delta.x - up_dir * pointer_delta.y) * (_runtime_camera_distance * 0.0015)
			_sync_runtime_camera()
		elif _runtime_orbiting:
			_runtime_camera_yaw -= pointer_delta.x * 0.006
			_runtime_camera_pitch = clampf(
				_runtime_camera_pitch - pointer_delta.y * 0.006,
				-0.35,
				0.85
			)
			_sync_runtime_camera()
	elif event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.keycode >= KEY_0 and key.keycode <= KEY_9:
			var idx := key.keycode - KEY_0
			_focus_pose(idx)
		elif key.keycode == KEY_LEFT or key.keycode == KEY_A:
			var next_idx := (_focused_pose_index - 1 + _entries.size()) % _entries.size() if _focused_pose_index >= 0 else 0
			_focus_pose(next_idx)
		elif key.keycode == KEY_RIGHT or key.keycode == KEY_D:
			var next_idx := (_focused_pose_index + 1) % _entries.size() if _focused_pose_index >= 0 else 0
			_focus_pose(next_idx)
		elif key.keycode == KEY_SPACE or key.keycode == KEY_HOME:
			_reset_overview_camera()
		elif key.keycode == KEY_T:
			show_target_handles = not show_target_handles
		elif key.keycode == KEY_P:
			apply_ik_to_all_poses = not apply_ik_to_all_poses
		elif key.keycode == KEY_L:
			dynamic_aim_sweep = not dynamic_aim_sweep
		elif key.keycode == KEY_UP and (key.ctrl_pressed or key.alt_pressed):
			aim_pitch_deg = clampf(aim_pitch_deg + 5.0, -45.0, 45.0)
		elif key.keycode == KEY_DOWN and (key.ctrl_pressed or key.alt_pressed):
			aim_pitch_deg = clampf(aim_pitch_deg - 5.0, -45.0, 45.0)
		elif key.keycode == KEY_LEFT and (key.ctrl_pressed or key.alt_pressed):
			aim_yaw_deg = clampf(aim_yaw_deg - 5.0, -70.0, 70.0)
		elif key.keycode == KEY_RIGHT and (key.ctrl_pressed or key.alt_pressed):
			aim_yaw_deg = clampf(aim_yaw_deg + 5.0, -70.0, 70.0)


func _focus_pose(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_focused_pose_index = index
	var entry: Dictionary = _entries[index]
	var pose := entry.get("pose") as Node3D
	if pose != null:
		_runtime_camera_target = pose.global_position + Vector3(0.0, 1.25, 0.0)
		_runtime_camera_distance = 2.5
		_runtime_camera_yaw = PI
		_runtime_camera_pitch = 0.08
		_sync_runtime_camera()


func _reset_overview_camera() -> void:
	_focused_pose_index = -1
	_runtime_camera_target = Vector3(0.0, 1.0, 0.0)
	_runtime_camera_distance = 26.0
	_runtime_camera_yaw = PI
	_runtime_camera_pitch = 0.16
	_sync_runtime_camera()


func reload_lineup() -> void:
	_initialized = false
	_entries.clear()
	_clip_paths = _load_clip_paths()
	var lineup := get_node_or_null("PoseLineup") as Node3D
	if lineup == null:
		_status = "Missing PoseLineup node"
		push_error("Gun Pose Lineup requires a PoseLineup child")
		return
	var errors: Array[String] = []
	for pose_node in lineup.get_children():
		if not (pose_node is Node3D):
			continue
		var result := _configure_pose(pose_node as Node3D)
		if not bool(result.get("ok", false)):
			errors.append("%s: %s" % [pose_node.name, result.get("error", "unknown")])
	_sync_target_visibility()
	_initialized = errors.is_empty()
	_status = (
		"READY — %d live poses in one horizontal lineup" % _entries.size()
		if errors.is_empty()
		else "FAILED — %s" % "; ".join(errors)
	)
	if errors.is_empty():
		print("SOCOM_GUN_POSE_LINEUP READY poses=%d hierarchy=native" % _entries.size())
		if Engine.is_editor_hint():
			_focus_native_editor.call_deferred()
	else:
		push_error(_status)


func get_debug_snapshot() -> Dictionary:
	var contexts: Array[String] = []
	var clips: Array[String] = []
	for entry: Dictionary in _entries:
		contexts.append(String(entry.get("context", "")))
		clips.append(String(entry.get("clip", "")))
	return {
		"initialized": _initialized,
		"status": _status,
		"pose_count": _entries.size(),
		"contexts": contexts,
		"clips": clips,
		"native_scene_tree": true,
		"canonical_rig_scene": "res://scenes/player/canonical_socom_operator_rig.tscn",
		"gameplay_scene_changed": false,
		"in_game_studio_lab": not Engine.is_editor_hint(),
		"runtime_camera_active": _runtime_camera != null and _runtime_camera.current,
	}


func _sync_runtime_camera() -> void:
	if _runtime_camera == null:
		return
	var orbit_direction := Vector3(
		sin(_runtime_camera_yaw) * cos(_runtime_camera_pitch),
		sin(_runtime_camera_pitch),
		cos(_runtime_camera_yaw) * cos(_runtime_camera_pitch)
	)
	_runtime_camera.global_position = (
		_runtime_camera_target + orbit_direction * _runtime_camera_distance
	)
	_runtime_camera.look_at(_runtime_camera_target, Vector3.UP)


func _focus_native_editor() -> void:
	# Opening the lab should require no manual orbit/zoom step. Select the real
	# PoseLineup node in the Scene dock and frame the complete horizontal row in
	# Godot's native perspective viewport.
	await get_tree().process_frame
	await get_tree().process_frame
	if not Engine.is_editor_hint() or EditorInterface.get_edited_scene_root() != self:
		return
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(get_node("PoseLineup"))
	var editor_viewport := EditorInterface.get_editor_viewport_3d(0)
	if editor_viewport == null:
		return
	var editor_camera := editor_viewport.get_camera_3d()
	if editor_camera == null:
		return
	editor_camera.global_position = Vector3(0.0, 4.5, -26.0)
	editor_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _configure_pose(pose: Node3D) -> Dictionary:
	var context := StringName(pose.get_meta("context", ""))
	var clip := StringName(pose.get_meta("clip_key", ""))
	var rig := pose.get_node_or_null("OperatorRig") as Node3D
	var player := pose.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var weapon := pose.get_node_or_null("EditorWeapon") as Node3D
	if context == &"" or clip == &"":
		return {"ok": false, "error": "missing context or clip_key metadata"}
	if rig == null or player == null or weapon == null:
		return {"ok": false, "error": "OperatorRig, AnimationPlayer, or EditorWeapon missing"}
	var skeleton := rig.get_node_or_null("VisualModel/Skeleton3D") as Skeleton3D
	if skeleton == null:
		skeleton = rig.get_node_or_null("VisualModel/Model/GeneralSkeleton") as Skeleton3D
	if skeleton == null:
		skeleton = rig.get_node_or_null("VisualModel/RootNode/mixamorig_Hips") as Skeleton3D
	if skeleton == null:
		skeleton = rig.find_child("mixamorig_Hips", true, false) as Skeleton3D
	if skeleton == null:
		skeleton = rig.find_child("*Skeleton*", true, false) as Skeleton3D
	var graph := rig.get_node_or_null("IKControlGraph") as Node3D
	if skeleton == null or graph == null:
		return {"ok": false, "error": "canonical Skeleton3D or IKControlGraph missing"}
	var pivot := graph.get_node_or_null("TargetPivot") as Node3D
	var arm_target := graph.get_node_or_null("TargetPivot/RHUpperArmWeaponTarget") as Node3D
	var hand_target := graph.get_node_or_null("TargetPivot/RHWeaponTarget") as Node3D
	var support_target := graph.get_node_or_null("TargetPivot/LHWeaponContactTarget") as Node3D
	if pivot == null or arm_target == null or hand_target == null or support_target == null:
		return {"ok": false, "error": "TargetPivot contact hierarchy incomplete"}
	if not _install_animation(player, skeleton, clip):
		return {"ok": false, "error": "clip %s could not be installed" % clip}
	_disable_weapon_collisions(weapon)
	var dummy_gun := rig.find_child("Gun", true, false) as Node3D
	if dummy_gun != null:
		dummy_gun.visible = false
	var dummy_holder := rig.find_child("WeaponHolder", true, false) as Node3D
	if dummy_holder != null:
		dummy_holder.visible = false
	var ready := context in READY_CONTEXTS
	var spine := skeleton.get_node_or_null("SpineCCDIK3D") as CCDIK3D
	if spine == null:
		spine = CCDIK3D.new()
		spine.name = "SpineCCDIK3D"
		skeleton.add_child(spine)
	var arm_modifier := skeleton.get_node_or_null("TargetPivotArmAimModifier")
	if arm_modifier == null:
		const TargetPivotArmAimModifier := preload("res://scripts/player/operator_target_pivot_arm_aim_modifier.gd")
		arm_modifier = TargetPivotArmAimModifier.new()
		arm_modifier.name = "TargetPivotArmAimModifier"
		skeleton.add_child(arm_modifier)
	var weapon_modifier := skeleton.get_node_or_null("WeaponHandAttachmentModifier")
	if weapon_modifier == null:
		const WeaponHandAttachmentModifier := preload("res://scripts/player/operator_weapon_hand_attachment_modifier.gd")
		weapon_modifier = WeaponHandAttachmentModifier.new()
		weapon_modifier.name = "WeaponHandAttachmentModifier"
		skeleton.add_child(weapon_modifier)
	var support_ik := skeleton.get_node_or_null("LHTwoBoneIK3D") as TwoBoneIK3D
	if support_ik == null:
		support_ik = TwoBoneIK3D.new()
		support_ik.name = "LHTwoBoneIK3D"
		skeleton.add_child(support_ik)
	var support_basis := skeleton.get_node_or_null("LHCopyTransformModifier3D2") as CopyTransformModifier3D
	if support_basis == null:
		support_basis = CopyTransformModifier3D.new()
		support_basis.name = "LHCopyTransformModifier3D2"
		skeleton.add_child(support_basis)
	var observer := skeleton.get_node_or_null("LeftHandContactObserver")
	if spine == null or arm_modifier == null or weapon_modifier == null or support_ik == null:
		return {"ok": false, "error": "canonical modifier chain incomplete"}
	arm_modifier.call("bind", skeleton, pivot, arm_target, hand_target)
	weapon_modifier.call("bind", skeleton, weapon, hand_target, support_target)
	if observer != null:
		observer.call("bind", skeleton, &"mixamorig_LeftHand", support_target)
	var ik_active := ready or apply_ik_to_all_poses
	var is_reload := context == &"reload"
	spine.influence = 1.0 if ik_active else 0.0
	arm_modifier.influence = 1.0 if ik_active else 0.0
	weapon_modifier.influence = 1.0
	support_ik.influence = 0.0 if is_reload else (1.0 if ik_active else 0.0)
	support_basis.influence = 0.0 if is_reload else (1.0 if ik_active else 0.0)
	if observer != null:
		observer.influence = 1.0 if ik_active else 0.0
	_entries.append({
		"pose": pose,
		"context": context,
		"clip": clip,
		"player": player,
		"rig": rig,
		"graph": graph,
		"skeleton": skeleton,
		"spine": spine,
		"arm_modifier": arm_modifier,
		"weapon_modifier": weapon_modifier,
		"support_ik": support_ik,
		"support_basis": support_basis,
		"observer": observer,
		"ready": ready,
	})
	_update_entry_aim(_entries.back())
	return {"ok": true}


func _sync_modifier_influences() -> void:
	for entry: Dictionary in _entries:
		var ready: bool = bool(entry.get("ready", false))
		var ik_active := ready or apply_ik_to_all_poses
		var context: StringName = entry.get("context", &"")
		var is_reload := context == &"reload"
		var spine: Node = entry.get("spine") as Node
		var arm_modifier: Node = entry.get("arm_modifier") as Node
		var weapon_modifier: Node = entry.get("weapon_modifier") as Node
		var support_ik: Node = entry.get("support_ik") as Node
		var support_basis: Node = entry.get("support_basis") as Node
		var observer: Node = entry.get("observer") as Node
		if spine != null:
			spine.set("influence", 1.0 if ik_active else 0.0)
		if arm_modifier != null:
			arm_modifier.set("influence", 1.0 if ik_active else 0.0)
		if weapon_modifier != null:
			weapon_modifier.set("influence", 1.0)
		if support_ik != null:
			support_ik.set("influence", 0.0 if is_reload else (1.0 if ik_active else 0.0))
		if support_basis != null:
			support_basis.set("influence", 0.0 if is_reload else (1.0 if ik_active else 0.0))
		if observer != null:
			observer.set("influence", 1.0 if ik_active else 0.0)
	_sync_target_visibility()


func _install_animation(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip: StringName
) -> bool:
	var clip_path := String(_clip_paths.get(String(clip), ""))
	if clip_path.is_empty() or not ResourceLoader.exists(clip_path):
		return false
	var packed := load(clip_path) as PackedScene
	if packed == null:
		return false
	var source_root := packed.instantiate()
	var source_player := _find_animation_player(source_root)
	if source_player == null:
		source_root.free()
		return false
	var source_name := StringName()
	for candidate: StringName in source_player.get_animation_list():
		if candidate != &"RESET":
			source_name = candidate
			break
	if source_name == &"":
		source_root.free()
		return false
	var retargeted := _retarget_animation(
		source_player.get_animation(source_name),
		player,
		skeleton
	)
	retargeted.loop_mode = Animation.LOOP_LINEAR
	var library: AnimationLibrary
	if player.has_animation_library(&""):
		library = player.get_animation_library(&"")
	else:
		library = AnimationLibrary.new()
		player.add_animation_library(&"", library)
	if library.has_animation(clip):
		library.remove_animation(clip)
	library.add_animation(clip, retargeted)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(clip)
	player.advance(0.0)
	source_root.free()
	return true


func _retarget_animation(
	source: Animation,
	player: AnimationPlayer,
	skeleton: Skeleton3D
) -> Animation:
	var retargeted := source.duplicate() as Animation
	var root := player.get_node(player.root_node)
	var skeleton_path := root.get_path_to(skeleton)
	for track in range(retargeted.get_track_count() - 1, -1, -1):
		var old_path := String(retargeted.track_get_path(track))
		var raw_bone := old_path.split(":")[-1]
		var normalized := raw_bone.replace("mixamorig:", "mixamorig_")
		if not normalized.begins_with("mixamorig_"):
			normalized = "mixamorig_" + normalized
		var target_bone := ""
		if skeleton.find_bone(raw_bone) >= 0:
			target_bone = raw_bone
		elif skeleton.find_bone(normalized) >= 0:
			target_bone = normalized
		if target_bone.is_empty():
			retargeted.remove_track(track)
			continue
		retargeted.track_set_path(
			track,
			NodePath("%s:%s" % [skeleton_path, target_bone])
		)
		if (
			("Hips" in raw_bone or "root" in raw_bone.to_lower())
			and retargeted.track_get_type(track) == Animation.TYPE_POSITION_3D
		):
			for key in range(retargeted.track_get_key_count(track)):
				var position := retargeted.track_get_key_value(track, key) as Vector3
				position.x = 0.0
				position.z = 0.0
				position.y *= 0.0191988
				retargeted.track_set_key_value(track, key, position)
	return retargeted


func _update_entry_aim(entry: Dictionary) -> void:
	var pose := entry.get("pose") as Node3D
	if pose == null:
		return
	var graph := entry.get("graph") as Node3D
	var pivot := graph.get_node_or_null("TargetPivot") as Marker3D if graph != null else null
	var current_pitch := deg_to_rad(aim_pitch_deg)
	var current_yaw := deg_to_rad(aim_yaw_deg)
	if dynamic_aim_sweep:
		var time := Time.get_ticks_msec() * 0.001
		current_yaw = sin(time * 1.5) * deg_to_rad(25.0)
		current_pitch = cos(time * 2.0) * deg_to_rad(12.0)
	if pivot != null:
		pivot.rotation = Vector3(current_pitch, current_yaw, 0.0)
	var aim_forward := Vector3(
		sin(current_yaw) * cos(current_pitch),
		-sin(current_pitch),
		-cos(current_yaw) * cos(current_pitch)
	)
	var target := pose.global_position + Vector3(0.0, 1.35, 0.0) + aim_forward * 20.0
	var arm_modifier: Node = entry.get("arm_modifier") as Node
	var weapon_modifier: Node = entry.get("weapon_modifier") as Node
	if arm_modifier != null:
		arm_modifier.call("set_aim_target", target)
	if weapon_modifier != null:
		weapon_modifier.call(
			"set_aim_target",
			target,
			1.0 if (bool(entry.get("ready", false)) or apply_ik_to_all_poses) else 0.0
		)


func _sync_target_visibility() -> void:
	for entry: Dictionary in _entries:
		var graph := entry.get("graph") as Node3D
		if graph != null:
			var ready: bool = bool(entry.get("ready", false))
			graph.visible = show_target_handles and (ready or apply_ik_to_all_poses)


func _load_clip_paths() -> Dictionary:
	var file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var clips: Variant = (parsed as Dictionary).get("clips", {})
	return (clips as Dictionary).duplicate(true) if clips is Dictionary else {}


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _disable_weapon_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child in node.get_children():
		_disable_weapon_collisions(child)


func _sync_weapon_scale() -> void:
	if _scale_value_label != null:
		_scale_value_label.text = "%.2fx" % weapon_scale
	for entry: Dictionary in _entries:
		var pose := entry.get("pose") as Node3D
		if pose != null:
			var weapon := pose.get_node_or_null("EditorWeapon") as Node3D
			if weapon != null:
				var mesh := weapon.get_node_or_null("WeaponMesh") as Node3D
				if mesh != null:
					mesh.scale = Vector3.ONE * weapon_scale
				else:
					weapon.scale = Vector3.ONE * weapon_scale


func _build_runtime_side_editor() -> void:
	if _runtime_ui_layer != null:
		return
	_runtime_ui_layer = CanvasLayer.new()
	_runtime_ui_layer.name = "GunPoseStudioHUD"
	add_child(_runtime_ui_layer)

	var panel := PanelContainer.new()
	panel.name = "SideEditorPanel"
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 320.0
	panel.offset_bottom = -16.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.92)
	style.border_color = Color(0.18, 0.65, 0.52, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	_runtime_ui_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "GUN & POSE STUDIO"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("5be3b0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Visual Weapon & Posture Authoring"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color("8da89d"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# Weapon Selection Dropdown
	var weapon_title := Label.new()
	weapon_title.text = "EQUIPPED WEAPON"
	weapon_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(weapon_title)

	var weapon_picker := OptionButton.new()
	for i in range(WEAPON_OPTIONS.size()):
		var opt: Dictionary = WEAPON_OPTIONS[i]
		weapon_picker.add_item(opt["name"], i)
	weapon_picker.item_selected.connect(func(index: int):
		if index >= 0 and index < WEAPON_OPTIONS.size():
			_switch_lineup_weapon(WEAPON_OPTIONS[index]["path"])
	)
	vbox.add_child(weapon_picker)

	vbox.add_child(HSeparator.new())

	# Weapon Scale Control
	var scale_header := HBoxContainer.new()
	var scale_title := Label.new()
	scale_title.text = "WEAPON SCALE"
	scale_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_title.add_theme_font_size_override("font_size", 13)
	scale_header.add_child(scale_title)
	_scale_value_label = Label.new()
	_scale_value_label.text = "%.2fx" % weapon_scale
	_scale_value_label.add_theme_font_size_override("font_size", 13)
	_scale_value_label.add_theme_color_override("font_color", Color("5be3b0"))
	scale_header.add_child(_scale_value_label)
	vbox.add_child(scale_header)

	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.2
	scale_slider.max_value = 2.0
	scale_slider.step = 0.05
	scale_slider.value = weapon_scale
	scale_slider.value_changed.connect(func(v: float):
		weapon_scale = v
	)
	vbox.add_child(scale_slider)

	# Scale Preset Buttons
	var scale_presets := HBoxContainer.new()
	scale_presets.add_theme_constant_override("separation", 6)
	var p1 := Button.new()
	p1.text = "0.75x"
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1.pressed.connect(func(): scale_slider.value = 0.75)
	scale_presets.add_child(p1)
	var p2 := Button.new()
	p2.text = "1.00x"
	p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2.pressed.connect(func(): scale_slider.value = 1.0)
	scale_presets.add_child(p2)
	var p3 := Button.new()
	p3.text = "1.25x"
	p3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p3.pressed.connect(func(): scale_slider.value = 1.25)
	scale_presets.add_child(p3)
	vbox.add_child(scale_presets)

	var save_scale_btn := Button.new()
	save_scale_btn.text = "💾 Save Scale to Weapon Scene"
	save_scale_btn.pressed.connect(func():
		_save_current_weapon_scale()
		save_scale_btn.text = "✅ Saved (%.2fx)!" % weapon_scale
	)
	vbox.add_child(save_scale_btn)

	vbox.add_child(HSeparator.new())

	# Aim Pitch & Yaw
	var aim_title := Label.new()
	aim_title.text = "AIM ORIENTATION"
	aim_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(aim_title)

	var pitch_box := HBoxContainer.new()
	var pitch_lbl := Label.new()
	pitch_lbl.text = "Pitch:"
	pitch_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pitch_box.add_child(pitch_lbl)
	_pitch_value_label = Label.new()
	_pitch_value_label.text = "%.0f°" % aim_pitch_deg
	pitch_box.add_child(_pitch_value_label)
	vbox.add_child(pitch_box)

	var pitch_slider := HSlider.new()
	pitch_slider.min_value = -45.0
	pitch_slider.max_value = 45.0
	pitch_slider.step = 1.0
	pitch_slider.value = aim_pitch_deg
	pitch_slider.value_changed.connect(func(v: float):
		aim_pitch_deg = v
		if _pitch_value_label != null:
			_pitch_value_label.text = "%.0f°" % v
	)
	vbox.add_child(pitch_slider)

	var yaw_box := HBoxContainer.new()
	var yaw_lbl := Label.new()
	yaw_lbl.text = "Yaw:"
	yaw_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yaw_box.add_child(yaw_lbl)
	_yaw_value_label = Label.new()
	_yaw_value_label.text = "%.0f°" % aim_yaw_deg
	yaw_box.add_child(_yaw_value_label)
	vbox.add_child(yaw_box)

	var yaw_slider := HSlider.new()
	yaw_slider.min_value = -70.0
	yaw_slider.max_value = 70.0
	yaw_slider.step = 1.0
	yaw_slider.value = aim_yaw_deg
	yaw_slider.value_changed.connect(func(v: float):
		aim_yaw_deg = v
		if _yaw_value_label != null:
			_yaw_value_label.text = "%.0f°" % v
	)
	vbox.add_child(yaw_slider)

	var reset_aim_btn := Button.new()
	reset_aim_btn.text = "Reset Aim (0°, 0°)"
	reset_aim_btn.pressed.connect(func():
		pitch_slider.value = 0.0
		yaw_slider.value = 0.0
	)
	vbox.add_child(reset_aim_btn)

	vbox.add_child(HSeparator.new())

	# Pose Focus Buttons
	var pose_hdr := Label.new()
	pose_hdr.text = "SELECT POSTURE / CAMERA"
	pose_hdr.add_theme_font_size_override("font_size", 13)
	vbox.add_child(pose_hdr)

	var poses := [
		"0: Idle Rifle", "1: Aim Idle", "2: Combat Ready", "3: Combat Fire",
		"4: Run Forward", "5: Run Left", "6: Run Right", "7: Crouch Move",
		"8: Prone Move", "9: Reload"
	]
	for i in range(poses.size()):
		var btn := Button.new()
		btn.text = poses[i]
		var idx := i
		btn.pressed.connect(func():
			_focus_pose(idx)
		)
		vbox.add_child(btn)

	var overview_btn := Button.new()
	overview_btn.text = "🔍 Overview (All 10 Poses)"
	overview_btn.pressed.connect(_reset_overview_camera)
	vbox.add_child(overview_btn)

	vbox.add_child(HSeparator.new())

	# Playback Controls
	var speed_box := HBoxContainer.new()
	var speed_lbl := Label.new()
	speed_lbl.text = "Speed:"
	speed_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_box.add_child(speed_lbl)
	var speed_val := Label.new()
	speed_val.text = "%.2fx" % playback_speed
	speed_box.add_child(speed_val)
	vbox.add_child(speed_box)

	var speed_slider := HSlider.new()
	speed_slider.min_value = 0.0
	speed_slider.max_value = 2.0
	speed_slider.step = 0.1
	speed_slider.value = playback_speed
	speed_slider.value_changed.connect(func(v: float):
		playback_speed = v
		speed_val.text = "%.2fx" % v
	)
	vbox.add_child(speed_slider)

	# Return to Main Menu
	vbox.add_child(HSeparator.new())
	var menu_btn := Button.new()
	menu_btn.text = "← Back to Game Launcher"
	menu_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://game_launcher.tscn")
	)
	vbox.add_child(menu_btn)


func _save_current_weapon_scale() -> void:
	if _entries.is_empty():
		return
	var first_entry: Dictionary = _entries[0]
	var pose := first_entry.get("pose") as Node3D
	if pose == null:
		return
	var weapon := pose.get_node_or_null("EditorWeapon") as Node3D
	if weapon == null:
		return
	var scene_file := weapon.scene_file_path
	if scene_file.is_empty():
		scene_file = "res://scenes/weapons/m16a2.tscn"
	var packed := load(scene_file) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	var mesh := inst.get_node_or_null("WeaponMesh") as Node3D
	if mesh != null:
		mesh.scale = Vector3.ONE * weapon_scale
	else:
		inst.scale = Vector3.ONE * weapon_scale
	var new_packed := PackedScene.new()
	if new_packed.pack(inst) == OK:
		ResourceSaver.save(new_packed, scene_file)
		print("Saved weapon scale %.2fx directly to %s!" % [weapon_scale, scene_file])
	inst.free()


func _switch_lineup_weapon(weapon_path: String) -> void:
	var packed := load(weapon_path) as PackedScene
	if packed == null:
		return
	for entry: Dictionary in _entries:
		var pose := entry.get("pose") as Node3D
		if pose == null:
			continue
		var old_weapon := pose.get_node_or_null("EditorWeapon") as Node3D
		var old_transform := Transform3D.IDENTITY
		if old_weapon != null:
			old_transform = old_weapon.transform
			old_weapon.name = "OldWeapon"
			old_weapon.queue_free()
		var new_weapon := packed.instantiate() as Node3D
		new_weapon.name = "EditorWeapon"
		new_weapon.transform = old_transform
		pose.add_child(new_weapon)
		entry["weapon"] = new_weapon
		_disable_weapon_collisions(new_weapon)
		var mesh := new_weapon.get_node_or_null("WeaponMesh") as Node3D
		if mesh != null:
			mesh.scale = Vector3.ONE * weapon_scale
		else:
			new_weapon.scale = Vector3.ONE * weapon_scale

		var rig := entry.get("rig") as Node3D
		if rig != null:
			var skeleton := rig.get_node_or_null("VisualModel/Skeleton3D") as Skeleton3D
			if skeleton == null:
				skeleton = rig.get_node_or_null("VisualModel/Model/GeneralSkeleton") as Skeleton3D
			if skeleton == null:
				skeleton = rig.find_child("*Skeleton*", true, false) as Skeleton3D
			if skeleton != null:
				var mod = skeleton.get_node_or_null("WeaponHandAttachmentModifier")
				if mod != null and mod.has_method("rebind_weapon"):
					mod.rebind_weapon(new_weapon)
