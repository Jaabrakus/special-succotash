class_name SocomNativeIKPlayerController
extends "res://script/Player.gd"

## Replacement-player vertical slice built on the supplied Godot 4.6 NEW IK
## AIM character, skeleton, block gun, AnimationTree, and modifier hierarchy.
## Selected SOCOM/Mixamo actions are rest-aware retargets onto this skeleton.

const RetargetService := preload(
	"res://scripts/labs/animation_retarget_service.gd"
)
const RootSanitizer := preload(
	"res://scripts/player/operator_animation_root_sanitizer.gd"
)
const RETARGET_PROFILE_PATH := (
	"res://config/character_retarget_profiles/godot_new_ik_v1.json"
)

const SOCOM_CLIPS := {
	&"idle_crouch": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
	&"crouch_forward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward.fbx",
	&"idle_prone": "res://assets/animations/mixamo/Prone Forward Stop.fbx",
	&"prone_forward": "res://assets/animations/mixamo/Prone Forward.fbx",
	&"prone_fire": "res://assets/animations/mixamo/Prone Firing Rifle.fbx",
	&"prone_reload": "res://assets/animations/mixamo/Prone Reloading.fbx",
	&"combat_fire": "res://assets/animations/mixamo/Shooter Pack/firing rifle.fbx",
	&"reload": "res://assets/external/agls_intake/imported/weapon_reload/ALSP2_Reloading_Rifle_M4A4.scn",
	&"grenade_toss": "res://assets/animations/mixamo/toss grenade.fbx",
	&"dive_roll": "res://assets/animations/mixamo/Running Dive Roll.fbx"
}

const LOOPING_CLIPS := [&"idle_crouch", &"crouch_forward", &"idle_prone", &"prone_forward"]
const SHOWCASE_ORDER := [
	&"idle_crouch", &"crouch_forward", &"idle_prone", &"prone_forward",
	&"prone_fire", &"prone_reload", &"combat_fire", &"reload",
	&"grenade_toss", &"dive_roll"
]
const UPPER_BODY_RELOAD := &"reload"
const UPPER_BODY_FIRE := &"combat_fire"
const RELOAD_REQUEST_PATH := &"parameters/ReloadUpperBody/request"
const RELOAD_ACTIVE_PATH := &"parameters/ReloadUpperBody/active"
const FIRE_REQUEST_PATH := &"parameters/CombatFireUpperBody/request"
const FIRE_ACTIVE_PATH := &"parameters/CombatFireUpperBody/active"

var socom_animation_player: AnimationPlayer
var socom_skeleton: Skeleton3D
var socom_library := AnimationLibrary.new()
var socom_bone_map: Dictionary = {}
var socom_clips_ready := false
var active_socom_clip: StringName = &""
var showcase_enabled := false
var showcase_elapsed := 0.0
var showcase_index := -1
var left_hand_ik: TwoBoneIK3D
var left_hand_rotation_copy: CopyTransformModifier3D
var upper_body_layer_seen_active := false

var head_marker: Marker3D
var torso_marker: Marker3D
var pelvis_marker: Marker3D
var feet_marker: Marker3D
var muzzle_marker: Marker3D

var max_health: float = 100.0
var current_health: float = 100.0


enum Posture { STANDING = 0, CROUCHING = 1, PRONE = 2 }
var posture: Posture = Posture.STANDING
var target_pivot_y := 1.204
var target_pivot: Node3D

func _ready() -> void:
	_ensure_reference_input_aliases()
	_build_camera_markers()
	super._ready()
	target_pivot = get_node_or_null("TargetPivot") as Node3D
	socom_animation_player = get_node("AnimationPlayer") as AnimationPlayer
	socom_skeleton = get_node("Model/GeneralSkeleton") as Skeleton3D
	left_hand_ik = socom_skeleton.get_node_or_null("LHTwoBoneIK3D") as TwoBoneIK3D
	left_hand_rotation_copy = socom_skeleton.get_node_or_null(
		"LHCopyTransformModifier3D2"
	) as CopyTransformModifier3D
	showcase_enabled = OS.get_cmdline_user_args().has("--animation-showcase")
	_load_retarget_profile()
	_build_socom_animation_library.call_deferred()
	is_strafing = true
	turn_speed = 30.0
	equip_weapon("res://scenes/weapons/m16a2.tscn")


func _process(delta: float) -> void:
	if _is_layered_upper_body_action(active_socom_clip):
		super._process(delta)
		var layer_active := bool(animation_tree.get(_active_layer_path()))
		upper_body_layer_seen_active = upper_body_layer_seen_active or layer_active
		if upper_body_layer_seen_active and not layer_active:
			_stop_socom_action()
		return
	if active_socom_clip != &"":
		root_velocity = Vector3.ZERO
		if not socom_animation_player.is_playing():
			_stop_socom_action()
		return
	super._process(delta)
	if showcase_enabled and socom_clips_ready:
		showcase_elapsed += delta
		if showcase_elapsed >= 2.35:
			showcase_elapsed = 0.0
			showcase_index = (showcase_index + 1) % SHOWCASE_ORDER.size()
			play_socom_action(SHOWCASE_ORDER[showcase_index])


func _physics_process(delta: float) -> void:
	if target_pivot != null:
		target_pivot.position.y = lerpf(target_pivot.position.y, target_pivot_y, delta * 12.0)
		_apply_spine_aim_constraints(delta)
	if _is_layered_upper_body_action(active_socom_clip):
		super._physics_process(delta)
		return
	if active_socom_clip != &"":
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	super._physics_process(delta)


func _apply_spine_aim_constraints(_delta: float) -> void:
	if target_pivot == null:
		return
	var min_pitch := -55.0
	var max_pitch := 65.0
	var max_yaw := 75.0
	if posture == Posture.PRONE:
		min_pitch = -30.0
		max_pitch = 35.0
		max_yaw = 35.0
	elif posture == Posture.CROUCHING:
		min_pitch = -40.0
		max_pitch = 50.0
		max_yaw = 55.0
	target_pivot.rotation_degrees.x = clampf(target_pivot.rotation_degrees.x, min_pitch, max_pitch)
	target_pivot.rotation_degrees.y = clampf(target_pivot.rotation_degrees.y, -max_yaw, max_yaw)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_C: play_socom_action(&"idle_crouch")
		KEY_Z: play_socom_action(&"idle_prone")
		KEY_R: play_socom_action(&"reload")
		KEY_G: play_socom_action(&"grenade_toss")
		KEY_F: play_socom_action(&"combat_fire")
		KEY_X: play_socom_action(&"prone_fire")
		KEY_SPACE: play_socom_action(&"dive_roll")


func play_socom_action(clip_name: StringName) -> bool:
	if not socom_clips_ready or not socom_library.has_animation(clip_name):
		return false
	if active_socom_clip == UPPER_BODY_RELOAD and clip_name in [UPPER_BODY_FIRE, &"prone_fire"]:
		return false

	# Update posture target heights
	if clip_name in [&"idle_crouch", &"crouch_forward"]:
		posture = Posture.CROUCHING
		target_pivot_y = 0.820
	elif clip_name in [&"idle_prone", &"prone_forward", &"prone_fire", &"prone_reload"]:
		posture = Posture.PRONE
		target_pivot_y = 0.220
	elif clip_name in [&"dive_roll"]:
		posture = Posture.PRONE
		target_pivot_y = 0.220
	else:
		posture = Posture.STANDING
		target_pivot_y = 1.204

	if clip_name == UPPER_BODY_RELOAD:
		active_socom_clip = clip_name
		upper_body_layer_seen_active = false
		_set_support_hand_ik_enabled(false)
		animation_tree.set(
			RELOAD_REQUEST_PATH,
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
		)
		return true
	if clip_name == UPPER_BODY_FIRE:
		active_socom_clip = clip_name
		upper_body_layer_seen_active = false
		_set_support_hand_ik_enabled(true)
		animation_tree.set(
			FIRE_REQUEST_PATH,
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
		)
		return true

	animation_tree.active = false
	active_socom_clip = clip_name
	socom_animation_player.play(&"SOCOM/" + clip_name)
	return true


func _stop_socom_action() -> void:
	var completed_clip := active_socom_clip
	active_socom_clip = &""
	if _is_layered_upper_body_action(completed_clip):
		upper_body_layer_seen_active = false
		if completed_clip == UPPER_BODY_RELOAD:
			_set_support_hand_ik_enabled(true)
	else:
		socom_animation_player.stop()
		animation_tree.active = true


func _set_support_hand_ik_enabled(enabled: bool) -> void:
	var influence := 1.0 if enabled else 0.0
	if left_hand_ik != null:
		left_hand_ik.influence = influence
	if left_hand_rotation_copy != null:
		left_hand_rotation_copy.influence = influence


func notify_operator_fired() -> bool:
	return play_socom_action(UPPER_BODY_FIRE)


func _is_layered_upper_body_action(clip_name: StringName) -> bool:
	return clip_name in [UPPER_BODY_RELOAD, UPPER_BODY_FIRE]


func _active_layer_path() -> StringName:
	return RELOAD_ACTIVE_PATH if active_socom_clip == UPPER_BODY_RELOAD else FIRE_ACTIVE_PATH


func _build_socom_animation_library() -> void:
	if socom_animation_player == null or socom_skeleton == null:
		return
	var service := RetargetService.new()
	for clip_name: StringName in SOCOM_CLIPS:
		var loaded := service.load_fbx(
			{
				"key": String(clip_name),
				"path": String(SOCOM_CLIPS[clip_name]),
			},
			socom_library,
			socom_animation_player,
			socom_skeleton,
			true,
			socom_bone_map,
			LOOPING_CLIPS.has(clip_name),
			RootSanitizer,
			true
		)
		if not loaded:
			push_warning("Native IK player could not retarget %s" % clip_name)
	if socom_animation_player.has_animation_library(&"SOCOM"):
		socom_animation_player.remove_animation_library(&"SOCOM")
	socom_animation_player.add_animation_library(&"SOCOM", socom_library)
	socom_clips_ready = socom_library.get_animation_list().size() == SOCOM_CLIPS.size()
	if showcase_enabled and socom_clips_ready:
		showcase_elapsed = 2.35


func _load_retarget_profile() -> void:
	var file := FileAccess.open(RETARGET_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var raw_map: Variant = (parsed as Dictionary).get("bone_map", {})
		if raw_map is Dictionary:
			socom_bone_map = (raw_map as Dictionary).duplicate(true)


func _ensure_reference_input_aliases() -> void:
	var aliases := {
		&"forward": &"move_forward",
		&"backward": &"move_backward",
		&"left": &"move_left",
		&"right": &"move_right",
		&"aim": &"weapon_ready",
	}
	for alias: StringName in aliases:
		if not InputMap.has_action(alias):
			InputMap.add_action(alias, 0.25)
		var source: StringName = aliases[alias]
		if not InputMap.has_action(source):
			continue
		for source_event in InputMap.action_get_events(source):
			InputMap.action_add_event(alias, source_event.duplicate())
	for look_action in [&"lookleft", &"lookright", &"lookup", &"lookdown"]:
		if not InputMap.has_action(look_action):
			InputMap.add_action(look_action, 0.15)


func _build_camera_markers() -> void:
	head_marker = Marker3D.new()
	head_marker.name = "HeadMarker"
	head_marker.position = Vector3(0.0, 1.70, 0.0)
	add_child(head_marker)

	torso_marker = Marker3D.new()
	torso_marker.name = "TorsoMarker"
	torso_marker.position = Vector3(0.0, 1.20, 0.0)
	add_child(torso_marker)

	pelvis_marker = Marker3D.new()
	pelvis_marker.name = "PelvisMarker"
	pelvis_marker.position = Vector3(0.0, 0.85, 0.0)
	add_child(pelvis_marker)

	feet_marker = Marker3D.new()
	feet_marker.name = "FeetMarker"
	feet_marker.position = Vector3(0.0, 0.05, 0.0)
	add_child(feet_marker)

	muzzle_marker = Marker3D.new()
	muzzle_marker.name = "MuzzleMarker"
	muzzle_marker.position = Vector3(0.15, 1.25, -0.65)
	add_child(muzzle_marker)


func configure_max_health(value: float, refill: bool = true) -> void:
	max_health = maxf(value, 1.0)
	if refill:
		current_health = max_health


func set_current_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)


func apply_damage(value: float) -> float:
	var applied := minf(maxf(value, 0.0), current_health)
	current_health -= applied
	return applied


func get_active_muzzle_marker() -> Node3D:
	return muzzle_marker


var current_equipped_weapon: Node3D = null


func equip_weapon(weapon_resource_or_path: Variant = "res://scenes/weapons/m16a2.tscn") -> Node3D:
	var gun_holder := find_child("Gun", true, false) as Node3D
	if gun_holder == null:
		return null
	for child in gun_holder.get_children():
		if child is MeshInstance3D and (child.name == "MeshInstance3D" or child.name == "MeshInstance3D2"):
			child.visible = false
		elif child.name == "EquippedWeapon":
			child.queue_free()
	var packed: PackedScene = null
	if weapon_resource_or_path is PackedScene:
		packed = weapon_resource_or_path
	elif weapon_resource_or_path is String:
		packed = load(weapon_resource_or_path) as PackedScene
	if packed == null:
		return null
	var weapon_instance := packed.instantiate() as Node3D
	weapon_instance.name = "EquippedWeapon"
	gun_holder.add_child(weapon_instance)
	current_equipped_weapon = weapon_instance
	var left_socket := weapon_instance.find_child("Socket_LeftHand", true, false) as Node3D
	var lh_target := gun_holder.get_node_or_null("LHikTarget") as Node3D
	if left_socket != null and lh_target != null:
		lh_target.position.z = left_socket.position.z
	return weapon_instance


func get_active_muzzle_position() -> Vector3:
	if current_equipped_weapon != null:
		var muzzle := current_equipped_weapon.find_child("Socket_Muzzle", true, false) as Node3D
		if muzzle != null:
			return muzzle.global_position
	return muzzle_marker.global_position if muzzle_marker != null else global_position + Vector3(0.15, 1.25, -0.65)


func get_active_barrel_direction() -> Vector3:
	return -global_basis.z


func get_posture_name() -> StringName:
	return &"STANDING"


var _backpack_visual: Node3D = null

func set_bomb_backpack_visible(enabled: bool) -> void:
	if _backpack_visual == null:
		var BackpackScript := preload("res://scripts/player/operator_backpack_visual.gd")
		_backpack_visual = BackpackScript.build()
		var bone_attachment := find_child("Spine2Attachment", true, false) as Node3D
		if bone_attachment != null:
			bone_attachment.add_child(_backpack_visual)
		else:
			add_child(_backpack_visual)
			_backpack_visual.position = Vector3(0.0, 1.2, -0.15)
	if _backpack_visual != null:
		_backpack_visual.visible = enabled
