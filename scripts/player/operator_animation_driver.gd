class_name SocomOperatorAnimationDriver
extends Node3D

## Visual-only operator animation adapter.
##
## The gameplay controller supplies visual intent. This node never moves the
## CharacterBody3D, fires a weapon, traces obstruction, or changes camera/aim
## authority. Aim values are radians and are clamped before being applied as
## additive skeleton pose offsets.

const OPERATOR_SCENE := preload("res://assets/characters/operator3d/socom_141_operator_animated.glb")

const LEGACY_LOOPING_CLIPS: Array[StringName] = [
    &"idle_rifle", &"idle_crouch", &"idle_prone", &"rifle_aim", &"rifle_lowered",
    &"walk_forward", &"walk_forward_left", &"walk_left", &"walk_back_left",
    &"walk_backward", &"walk_back_right", &"walk_right", &"walk_forward_right",
    &"run_forward", &"run_forward_left", &"run_left", &"run_back_left",
    &"run_backward", &"run_back_right", &"run_right", &"run_forward_right",
    &"crouch_forward", &"crouch_forward_left", &"crouch_left", &"crouch_back_left",
    &"crouch_backward", &"crouch_back_right", &"crouch_right", &"crouch_forward_right",
    &"prone_crawl_forward", &"prone_crawl_backward", &"prone_turn_left", &"prone_turn_right",
    &"jump_airborne",
]

@export_group("Visual aim limits")
@export_range(0.0, 90.0, 0.5) var chest_yaw_limit_deg: float = 42.0
@export_range(0.0, 60.0, 0.5) var chest_pitch_limit_deg: float = 28.0
@export_range(0.0, 90.0, 0.5) var head_yaw_limit_deg: float = 56.0
@export_range(0.0, 60.0, 0.5) var head_pitch_limit_deg: float = 34.0

var model_root: Node3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var transition_node: AnimationNodeTransition
var skeleton: Skeleton3D
var current_clip: StringName = &""
var requested_action: StringName = &""
var requested_action_remaining: float = 0.0
var available_clips: Dictionary = {}

# Controller-provided visual inputs. Direction uses local X=right, Y=forward;
# its magnitude may carry normalized gait speed when speed is not supplied.
var movement_direction := Vector2.ZERO
var movement_speed_normalized: float = 0.0
var posture: StringName = &"STANDING"
var aim_yaw_rad: float = 0.0
var aim_pitch_rad: float = 0.0
var weapon_ready_weight: float = 0.0
var firing: bool = false
var obstruction_amount: float = 0.0
var movement_state: StringName = &"LOCOMOTION"

var _explicit_visual_inputs: bool = false
var _previous_ready_weight: float = 0.0
var _previous_firing: bool = false
var _previous_movement_state: StringName = &"LOCOMOTION"
var _queued_recovery: StringName = &""
var _queued_recovery_side: float = 1.0
var _bone_indices: Dictionary = {}

func _ready() -> void:
    process_priority = 100
    model_root = OPERATOR_SCENE.instantiate() as Node3D
    model_root.name = "RiggedOperator"
    # Blender authored forward converts to +Z through glTF; gameplay forward is -Z.
    model_root.rotation.y = PI
    add_child(model_root)
    animation_player = _find_animation_player(model_root)
    skeleton = _find_skeleton(model_root)
    if animation_player == null:
        push_error("SOCOM operator GLB has no AnimationPlayer")
        return
    if skeleton == null:
        push_error("SOCOM operator GLB has no Skeleton3D")
        return
    _cache_aim_bones()
    _configure_animation_loops()
    _build_animation_tree()
    _request_clip(&"low_ready_idle" if available_clips.has(&"low_ready_idle") else &"idle_rifle")

func _process(delta: float) -> void:
    if animation_tree == null:
        return
    if not _explicit_visual_inputs:
        _pull_legacy_locomotion_inputs()

    _queue_recovery_from_state_transition()
    var automatic_action := _consume_automatic_action_request()
    if automatic_action != &"":
        play_action(automatic_action, 0.07)

    if requested_action != &"":
        requested_action_remaining = maxf(0.0, requested_action_remaining - delta)
        if requested_action_remaining > 0.0:
            _request_clip(requested_action)
        else:
            requested_action = &""

    if requested_action == &"":
        _request_clip(_select_visual_clip())

    _apply_visual_aim_offsets()
    _previous_ready_weight = weapon_ready_weight
    _previous_firing = firing
    _previous_movement_state = movement_state

func set_visual_inputs(
    direction: Vector2,
    posture_name: StringName,
    aim_yaw: float,
    aim_pitch: float,
    ready_weight: float,
    is_firing: bool,
    obstruction: float,
    speed_normalized: float = -1.0,
    state_name: StringName = &"LOCOMOTION"
) -> void:
    _explicit_visual_inputs = true
    movement_direction = direction
    movement_speed_normalized = clampf(
        speed_normalized if speed_normalized >= 0.0 else direction.length(),
        0.0,
        1.0
    )
    posture = _sanitize_posture(posture_name)
    aim_yaw_rad = aim_yaw
    aim_pitch_rad = aim_pitch
    weapon_ready_weight = clampf(ready_weight, 0.0, 1.0)
    firing = is_firing
    obstruction_amount = clampf(obstruction, 0.0, 1.0)
    movement_state = state_name

func clear_explicit_visual_inputs() -> void:
    _explicit_visual_inputs = false

func notify_fired() -> bool:
    var clip := _fire_clip_for_posture()
    return play_action(clip, 0.035)

func request_recovery(kind: StringName, side: float = 1.0) -> void:
    if kind not in [&"jump", &"dive", &"roll"]:
        return
    _queued_recovery = kind
    _queued_recovery_side = -1.0 if side < 0.0 else 1.0

func play_action(clip_name: StringName, blend_seconds: float = 0.12) -> bool:
    if not available_clips.has(clip_name) or animation_player == null:
        return false
    var animation := animation_player.get_animation(clip_name)
    requested_action = clip_name
    requested_action_remaining = animation.length
    if transition_node:
        transition_node.xfade_time = blend_seconds
    _request_clip(clip_name, blend_seconds)
    return true

func has_clip(clip_name: StringName) -> bool:
    return available_clips.has(clip_name)

func get_clip_names() -> Array[StringName]:
    var names: Array[StringName] = []
    for clip_name in available_clips:
        names.append(clip_name as StringName)
    names.sort()
    return names

func get_visual_debug_data() -> Dictionary:
    return {
        "clip": current_clip,
        "movement_direction": movement_direction,
        "movement_speed_normalized": movement_speed_normalized,
        "posture": posture,
        "aim_yaw_rad": aim_yaw_rad,
        "aim_pitch_rad": aim_pitch_rad,
        "weapon_ready_weight": weapon_ready_weight,
        "firing": firing,
        "obstruction_amount": obstruction_amount,
        "movement_state": movement_state,
        "visual_only": true,
    }

func _select_visual_clip() -> StringName:
    if obstruction_amount >= 0.55:
        if posture == &"PRONE":
            return &"compressed_ready_prone"
        if posture == &"CROUCHED":
            return &"compressed_ready_crouch"
        return &"compressed_ready_idle"

    if weapon_ready_weight >= 0.5:
        if movement_speed_normalized < 0.08:
            if posture == &"PRONE":
                return &"combat_ready_prone_idle"
            if posture == &"CROUCHED":
                return &"combat_ready_crouch_idle"
            return &"combat_ready_idle"
        return _combat_locomotion_clip()
    return _low_ready_locomotion_clip()

func _low_ready_locomotion_clip() -> StringName:
    if movement_speed_normalized < 0.08:
        if posture == &"PRONE":
            return &"low_ready_prone_idle"
        if posture == &"CROUCHED":
            return &"low_ready_crouch_idle"
        return &"low_ready_idle"
    if posture == &"PRONE":
        return StringName("low_ready_prone_%s" % _prone_direction_suffix(movement_direction))
    var direction_name := _direction_suffix(movement_direction)
    if posture == &"CROUCHED":
        return StringName("low_ready_crouch_%s" % direction_name)
    var prefix := "low_ready_run" if movement_speed_normalized >= 0.72 else "low_ready_walk"
    return StringName("%s_%s" % [prefix, direction_name])

func _combat_locomotion_clip() -> StringName:
    if posture == &"PRONE":
        var prone_direction := _prone_direction_suffix(movement_direction)
        if prone_direction in ["left", "right"]:
            return &"prone_turn_left" if prone_direction == "left" else &"prone_turn_right"
        return &"prone_crawl_backward" if prone_direction == "backward" else &"prone_crawl_forward"
    var direction_name := _direction_suffix(movement_direction)
    if posture == &"CROUCHED":
        return StringName("crouch_%s" % direction_name)
    var prefix := "run" if movement_speed_normalized >= 0.72 else "walk"
    return StringName("%s_%s" % [prefix, direction_name])

func _consume_automatic_action_request() -> StringName:
    if _queued_recovery != &"":
        var recovery := _queued_recovery
        _queued_recovery = &""
        if recovery == &"jump":
            return &"low_ready_recover_jump"
        if recovery == &"dive":
            return &"low_ready_recover_dive"
        return &"low_ready_recover_roll_left" if _queued_recovery_side < 0.0 else &"low_ready_recover_roll_right"

    if firing and not _previous_firing:
        return _fire_clip_for_posture()
    if _previous_ready_weight < 0.5 and weapon_ready_weight >= 0.5:
        return &"low_ready_raise"
    if _previous_ready_weight >= 0.5 and weapon_ready_weight < 0.5:
        return &"combat_ready_lower"
    return &""

func _queue_recovery_from_state_transition() -> void:
    if movement_state == _previous_movement_state:
        return
    if _previous_movement_state == &"AIRBORNE" and movement_state in [&"LANDING", &"LOCOMOTION", &"STANDING"]:
        request_recovery(&"jump")
    elif _previous_movement_state in [&"DIVING", &"DIVE_PRONE"] and movement_state not in [&"DIVING", &"DIVE_PRONE"]:
        request_recovery(&"dive")
    elif _previous_movement_state == &"ROLLING" and movement_state != &"ROLLING":
        request_recovery(&"roll", movement_direction.x)

func _fire_clip_for_posture() -> StringName:
    if posture == &"PRONE":
        return &"combat_ready_prone_fire"
    if posture == &"CROUCHED":
        return &"combat_ready_crouch_fire"
    return &"combat_ready_fire"

func _apply_visual_aim_offsets() -> void:
    if skeleton == null:
        return
    var yaw := clampf(aim_yaw_rad, -deg_to_rad(chest_yaw_limit_deg), deg_to_rad(chest_yaw_limit_deg))
    var pitch := clampf(aim_pitch_rad, -deg_to_rad(chest_pitch_limit_deg), deg_to_rad(chest_pitch_limit_deg))
    var ready_scale := lerpf(0.20, 1.0, weapon_ready_weight) * lerpf(1.0, 0.35, obstruction_amount)
    _apply_bone_additive(&"chest", yaw * 0.48 * ready_scale, pitch * 0.38 * ready_scale)
    _apply_bone_additive(&"weapon", yaw * 0.30 * ready_scale, pitch * 0.62 * ready_scale)
    var head_yaw := clampf(aim_yaw_rad, -deg_to_rad(head_yaw_limit_deg), deg_to_rad(head_yaw_limit_deg))
    var head_pitch := clampf(aim_pitch_rad, -deg_to_rad(head_pitch_limit_deg), deg_to_rad(head_pitch_limit_deg))
    _apply_bone_additive(&"head", head_yaw * 0.42, head_pitch * 0.30)

func _apply_bone_additive(bone_name: StringName, yaw: float, pitch: float) -> void:
    var index := int(_bone_indices.get(bone_name, -1))
    if index < 0:
        return
    var base_rotation := skeleton.get_bone_pose_rotation(index)
    var additive := Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
    skeleton.set_bone_pose_rotation(index, base_rotation * additive)

func _pull_legacy_locomotion_inputs() -> void:
    var player := _get_player()
    if player == null:
        return
    var local_velocity := player.global_basis.inverse() * player.velocity
    movement_direction = Vector2(local_velocity.x, -local_velocity.z)
    movement_speed_normalized = clampf(movement_direction.length() / 6.5, 0.0, 1.0)
    if movement_direction.length_squared() > 0.001:
        movement_direction = movement_direction.normalized() * movement_speed_normalized
    posture = player.get_posture_name() if player.has_method("get_posture_name") else &"STANDING"
    movement_state = player.get_motion_state_name() if player.has_method("get_motion_state_name") else &"LOCOMOTION"

func _sanitize_posture(value: StringName) -> StringName:
    return value if value in [&"STANDING", &"CROUCHED", &"PRONE"] else &"STANDING"

func _direction_suffix(direction: Vector2) -> String:
    if direction.length_squared() < 0.001:
        return "forward"
    var angle := wrapf(atan2(direction.x, direction.y), -PI, PI)
    var octant := wrapi(int(round(angle / (PI / 4.0))), -4, 4)
    match octant:
        -3: return "back_left"
        -2: return "left"
        -1: return "forward_left"
        0: return "forward"
        1: return "forward_right"
        2: return "right"
        3: return "back_right"
        _: return "backward"

func _prone_direction_suffix(direction: Vector2) -> String:
    if absf(direction.x) > absf(direction.y) * 0.72:
        return "left" if direction.x < 0.0 else "right"
    return "backward" if direction.y < -0.05 else "forward"

func _build_animation_tree() -> void:
    var blend_tree := AnimationNodeBlendTree.new()
    transition_node = AnimationNodeTransition.new()
    transition_node.input_count = animation_player.get_animation_list().size()
    transition_node.xfade_time = 0.08
    blend_tree.add_node(&"clip_transition", transition_node, Vector2(620.0, 80.0))
    var index := 0
    for animation_name in animation_player.get_animation_list():
        var clip_name := StringName(animation_name)
        available_clips[clip_name] = true
        transition_node.set_input_name(index, clip_name)
        var animation_node := AnimationNodeAnimation.new()
        animation_node.animation = clip_name
        blend_tree.add_node(clip_name, animation_node, Vector2(-600.0, float(index) * 55.0))
        blend_tree.connect_node(&"clip_transition", index, clip_name)
        index += 1
    blend_tree.connect_node(&"output", 0, &"clip_transition")
    animation_tree = AnimationTree.new()
    animation_tree.name = "OperatorAnimationTree"
    add_child(animation_tree)
    animation_tree.anim_player = animation_tree.get_path_to(animation_player)
    animation_tree.tree_root = blend_tree
    animation_tree.active = true

func _request_clip(clip_name: StringName, blend_seconds: float = 0.08) -> void:
    if clip_name == current_clip or not available_clips.has(clip_name):
        return
    current_clip = clip_name
    transition_node.xfade_time = maxf(0.0, blend_seconds)
    animation_tree.set("parameters/clip_transition/transition_request", clip_name)

func _configure_animation_loops() -> void:
    for animation_name in animation_player.get_animation_list():
        var clip_name := StringName(animation_name)
        var animation := animation_player.get_animation(clip_name)
        animation.loop_mode = Animation.LOOP_LINEAR if _is_looping_clip(clip_name) else Animation.LOOP_NONE

func _is_looping_clip(clip_name: StringName) -> bool:
    var text := String(clip_name)
    return (
        LEGACY_LOOPING_CLIPS.has(clip_name)
        or text.begins_with("low_ready_walk_")
        or text.begins_with("low_ready_run_")
        or text.begins_with("low_ready_crouch_")
        or text.begins_with("low_ready_prone_")
        or text in [
            "low_ready_idle", "low_ready_crouch_idle", "low_ready_prone_idle",
            "combat_ready_idle", "combat_ready_crouch_idle", "combat_ready_prone_idle",
            "compressed_ready_idle", "compressed_ready_crouch", "compressed_ready_prone",
        ]
    )

func _cache_aim_bones() -> void:
    for bone_name in [&"chest", &"head", &"weapon"]:
        _bone_indices[bone_name] = skeleton.find_bone(bone_name)

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found:
            return found
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found:
            return found
    return null

func _get_player() -> CharacterBody3D:
    var node: Node = get_parent()
    while node:
        if node is CharacterBody3D:
            return node as CharacterBody3D
        node = node.get_parent()
    return null
