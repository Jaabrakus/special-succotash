class_name ModularOperatorController
extends CharacterBody3D

enum Stance { STANDING = 0, CROUCHING = 1, PRONE = 2 }
enum WeaponMode { RIFLE = 0, PISTOL = 1, UNARMED = 2 }

const SPEED := 4.5
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.5
const PRONE_SPEED := 1.2
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8

@export var animation_tree: AnimationTree
@export var animation_player: AnimationPlayer
@export var skeleton: Skeleton3D
@export var camera_target: Node3D
@export var target_pivot: Node3D

const RetargetService := preload(
	"res://scripts/labs/animation_retarget_service.gd"
)
const RootSanitizer := preload(
	"res://scripts/player/operator_animation_root_sanitizer.gd"
)
const RETARGET_PROFILE_PATH := (
	"res://config/character_retarget_profiles/godot_new_ik_v1.json"
)

const GAME_CLIPS := {
	&"idle_crouch": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
	&"crouch_forward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward.fbx",
	&"idle_prone": "res://assets/animations/mixamo/Prone Forward Stop.fbx",
	&"prone_forward": "res://assets/animations/mixamo/Prone Forward.fbx",
	&"prone_fire": "res://assets/animations/mixamo/Prone Firing Rifle.fbx",
	&"prone_reload": "res://assets/animations/mixamo/Prone Reloading.fbx",
	&"combat_fire": "res://assets/animations/mixamo/Shooter Pack/firing rifle.fbx",
	&"reload": "res://assets/external/agls_intake/imported/weapon_reload/ALSP2_Reloading_Rifle_M4A4.scn",
	&"grenade_toss": "res://assets/animations/mixamo/toss grenade.fbx",
	&"dive_roll": "res://assets/animations/mixamo/Running Dive Roll.fbx",
	&"pistol_walk": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk.fbx",
	&"pistol_walk_backward": "res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk backward.fbx"
}

const LOOPING_CLIPS := [&"idle_crouch", &"crouch_forward", &"idle_prone", &"prone_forward", &"pistol_walk", &"pistol_walk_backward"]

var current_stance: Stance = Stance.STANDING
var current_weapon_mode: WeaponMode = WeaponMode.RIFLE
var target_pivot_y: float = 1.204
var is_strafing: bool = true
var turn_speed: float = 30.0
var cam_angle_diff: float = 0.0

var input_dir: Vector2 = Vector2.ZERO
var move_direction: Vector3 = Vector3.ZERO
var is_sprinting: bool = false
var is_firing: bool = false
var is_reloading: bool = false

var left_hand_ik: TwoBoneIK3D = null
var left_hand_copy: CopyTransformModifier3D = null
var weapon_holder: Node3D = null
var current_weapon_instance: Node3D = null
var muzzle_marker: Marker3D = null

var bone_map: Dictionary = {}
var game_library: AnimationLibrary = AnimationLibrary.new()
var clips_ready: bool = false
var active_action_clip: StringName = &""


func _ready() -> void:
	add_to_group("player")
	_ensure_input_actions()
	_setup_nodes()
	_setup_weapon_rig()
	_load_retarget_profile()
	_build_game_animation_library.call_deferred()
	set_weapon_mode(WeaponMode.RIFLE)
	set_stance(Stance.STANDING)


func _ensure_input_actions() -> void:
	var required_actions := [
		"move_left", "move_right", "move_forward", "move_backward",
		"left", "right", "forward", "backward",
		"sprint", "aim", "lookleft", "lookright", "lookup", "lookdown"
	]
	for action: String in required_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _setup_nodes() -> void:
	if animation_tree == null:
		animation_tree = get_node_or_null("AnimationTree") as AnimationTree
	if animation_player == null:
		animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if skeleton == null:
		skeleton = find_child("GeneralSkeleton", true, false) as Skeleton3D
	if target_pivot == null:
		target_pivot = get_node_or_null("TargetPivot") as Node3D

	if skeleton != null:
		left_hand_ik = skeleton.get_node_or_null("LHTwoBoneIK3D") as TwoBoneIK3D
		left_hand_copy = skeleton.get_node_or_null("LHCopyTransformModifier3D2") as CopyTransformModifier3D

	muzzle_marker = Marker3D.new()
	muzzle_marker.name = "MuzzleMarker"
	muzzle_marker.position = Vector3(0.15, 1.25, -0.65)
	add_child(muzzle_marker)


func _setup_weapon_rig() -> void:
	weapon_holder = find_child("Gun", true, false) as Node3D
	if weapon_holder != null:
		for child in weapon_holder.get_children():
			if child is MeshInstance3D and child.name.begins_with("MeshInstance3D"):
				child.visible = false


func _physics_process(delta: float) -> void:
	_update_target_pivot(delta)
	_handle_input_movement(delta)
	_apply_gravity_and_move(delta)
	_update_animation_tree(delta)


func _update_target_pivot(delta: float) -> void:
	if target_pivot == null:
		return
	target_pivot.position.y = lerpf(target_pivot.position.y, target_pivot_y, delta * 14.0)

	var min_pitch := -55.0
	var max_pitch := 65.0
	var max_yaw := 75.0
	if current_stance == Stance.PRONE:
		min_pitch = -30.0
		max_pitch = 35.0
		max_yaw = 35.0
	elif current_stance == Stance.CROUCHING:
		min_pitch = -40.0
		max_pitch = 50.0
		max_yaw = 55.0

	target_pivot.rotation_degrees.x = clampf(target_pivot.rotation_degrees.x, min_pitch, max_pitch)
	target_pivot.rotation_degrees.y = clampf(target_pivot.rotation_degrees.y, -max_yaw, max_yaw)


func _handle_input_movement(delta: float) -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO:
		input_dir = Input.get_vector("left", "right", "forward", "backward")

	is_sprinting = Input.is_action_pressed("sprint") and current_stance == Stance.STANDING

	var cam_y: float = 0.0
	if camera_target != null:
		cam_y = camera_target.global_transform.basis.get_euler().y
	elif get_viewport().get_camera_3d() != null:
		cam_y = get_viewport().get_camera_3d().global_transform.basis.get_euler().y

	if is_strafing:
		rotation.y = lerp_angle(rotation.y, cam_y, delta * turn_speed)

	move_direction = Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, cam_y).normalized()


func _apply_gravity_and_move(delta: float) -> void:
	var target_speed := SPEED
	if is_sprinting:
		target_speed = SPRINT_SPEED
	elif current_stance == Stance.CROUCHING:
		target_speed = CROUCH_SPEED
	elif current_stance == Stance.PRONE:
		target_speed = PRONE_SPEED

	if move_direction != Vector3.ZERO:
		velocity.x = move_direction.x * target_speed
		velocity.z = move_direction.z * target_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, target_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, target_speed * delta * 10.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	move_and_slide()


func _update_animation_tree(_delta: float) -> void:
	if animation_tree == null:
		return
	var blend_vec := Vector2(input_dir.x, -input_dir.y)
	if is_sprinting:
		blend_vec *= 1.5
	animation_tree.set("parameters/Locomotion/blend_position", blend_vec)


func set_stance(stance: Stance) -> void:
	current_stance = stance
	match stance:
		Stance.STANDING:
			target_pivot_y = 1.204
		Stance.CROUCHING:
			target_pivot_y = 0.820
		Stance.PRONE:
			target_pivot_y = 0.220


func set_weapon_mode(mode: WeaponMode) -> void:
	current_weapon_mode = mode
	if animation_tree != null:
		var mode_name := "rifle"
		match mode:
			WeaponMode.RIFLE:
				mode_name = "rifle"
			WeaponMode.PISTOL:
				mode_name = "pistol"
			WeaponMode.UNARMED:
				mode_name = "unarmed"
		if animation_tree.tree_root != null and animation_tree.tree_root.has_node("UpperBodyTransition"):
			animation_tree.set("parameters/UpperBodyTransition/transition_request", mode_name)

	match mode:
		WeaponMode.RIFLE:
			equip_weapon("res://scenes/weapons/m16a2.tscn")
			_set_support_hand_ik_enabled(true)
		WeaponMode.PISTOL:
			equip_weapon("res://scenes/weapons/pistol_1.tscn")
			_set_support_hand_ik_enabled(true)
		WeaponMode.UNARMED:
			_clear_equipped_weapon()
			_set_support_hand_ik_enabled(false)


func equip_weapon(weapon_resource_or_path: Variant) -> Node3D:
	if weapon_holder == null:
		_setup_weapon_rig()
	if weapon_holder == null:
		return null

	_clear_equipped_weapon()

	var packed: PackedScene = null
	if weapon_resource_or_path is PackedScene:
		packed = weapon_resource_or_path
	elif weapon_resource_or_path is String:
		packed = load(weapon_resource_or_path) as PackedScene

	if packed == null:
		return null

	var weapon_instance := packed.instantiate() as Node3D
	weapon_instance.name = "EquippedWeapon"
	weapon_holder.add_child(weapon_instance)
	current_weapon_instance = weapon_instance

	var left_socket := weapon_instance.find_child("Socket_LeftHand", true, false) as Node3D
	var lh_target := weapon_holder.get_node_or_null("LHikTarget") as Node3D
	if left_socket != null and lh_target != null:
		lh_target.position.z = left_socket.position.z

	return weapon_instance


func _clear_equipped_weapon() -> void:
	if weapon_holder != null:
		for child in weapon_holder.get_children():
			if child.name == "EquippedWeapon":
				child.queue_free()
	current_weapon_instance = null


func _set_support_hand_ik_enabled(enabled: bool) -> void:
	var influence := 1.0 if enabled else 0.0
	if left_hand_ik != null:
		left_hand_ik.influence = influence
	if left_hand_copy != null:
		left_hand_copy.influence = influence


func trigger_fire() -> bool:
	if current_weapon_mode == WeaponMode.UNARMED or is_reloading:
		return false
	if animation_tree != null:
		animation_tree.set("parameters/CombatFire/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func trigger_reload() -> bool:
	if current_weapon_mode == WeaponMode.UNARMED or is_reloading:
		return false
	is_reloading = true
	_set_support_hand_ik_enabled(false)
	if animation_tree != null:
		animation_tree.set("parameters/Reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	get_tree().create_timer(1.8).timeout.connect(func():
		is_reloading = false
		if current_weapon_mode != WeaponMode.UNARMED:
			_set_support_hand_ik_enabled(true)
	)
	return true


func _load_retarget_profile() -> void:
	var file := FileAccess.open(RETARGET_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var raw_map: Variant = (parsed as Dictionary).get("bone_map", {})
		if raw_map is Dictionary:
			bone_map = (raw_map as Dictionary).duplicate(true)


func _build_game_animation_library() -> void:
	if animation_player == null or skeleton == null:
		return
	var service := RetargetService.new()
	for clip_name: StringName in GAME_CLIPS:
		var loaded := service.load_fbx(
			{
				"key": String(clip_name),
				"path": String(GAME_CLIPS[clip_name]),
			},
			game_library,
			animation_player,
			skeleton,
			true,
			bone_map,
			LOOPING_CLIPS.has(clip_name),
			RootSanitizer,
			true
		)
		if not loaded:
			push_warning("Modular player could not retarget %s" % clip_name)
	if animation_player.has_animation_library(&"SOCOM"):
		animation_player.remove_animation_library(&"SOCOM")
	animation_player.add_animation_library(&"SOCOM", game_library)
	clips_ready = game_library.get_animation_list().size() >= (GAME_CLIPS.size() - 2)


func play_action_clip(clip_name: StringName) -> bool:
	if not game_library.has_animation(clip_name):
		return false
	active_action_clip = clip_name
	if animation_player.has_animation(&"SOCOM/" + clip_name):
		animation_player.play(&"SOCOM/" + clip_name)
		return true
	return false


func get_active_muzzle_position() -> Vector3:
	if current_weapon_instance != null:
		var muzzle := current_weapon_instance.find_child("Socket_Muzzle", true, false) as Node3D
		if muzzle != null:
			return muzzle.global_position
	return muzzle_marker.global_position if muzzle_marker != null else global_position + Vector3(0.15, 1.25, -0.65)


func get_active_barrel_direction() -> Vector3:
	return -global_basis.z


func get_posture_name() -> StringName:
	match current_stance:
		Stance.STANDING:
			return &"STANDING"
		Stance.CROUCHING:
			return &"CROUCHING"
		Stance.PRONE:
			return &"PRONE"
	return &"STANDING"
