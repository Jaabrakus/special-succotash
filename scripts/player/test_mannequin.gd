class_name SocomTestMannequin
extends Node3D

const OperatorAnimationDriver := preload("res://scripts/player/operator_animation_driver.gd")
const DEFAULT_ANIMATION_PROFILE := preload("res://assets/characters/operator3d/default_animation_profile.tres")

# SOCOM-141 procedural character rig.
# Purpose: camera + body/aim calibration, not final art.
#
# The lower body belongs to locomotion. The upper body is allowed to twist and pitch
# toward camera intent within anatomical limits. Arms stay on the rifle while the
# head follows aim slightly farther than the chest.

var head_marker: Marker3D
var torso_marker: Marker3D
var pelvis_marker: Marker3D
var feet_marker: Marker3D
var muzzle_marker: Marker3D

var skeleton_root: Node3D
var pelvis_bone: Node3D
var spine_bone: Node3D
var chest_bone: Node3D
var neck_bone: Node3D
var head_bone: Node3D
var weapon_bone: Node3D
var left_hand_bone: Node3D
var right_hand_bone: Node3D
var head_mesh: MeshInstance3D
var helmet_mesh: MeshInstance3D

var left_shoulder: Node3D
var right_shoulder: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var left_hip: Node3D
var right_hip: Node3D
var left_knee: Node3D
var right_knee: Node3D
var left_upper_arm_mesh: MeshInstance3D
var right_upper_arm_mesh: MeshInstance3D
var left_forearm_mesh: MeshInstance3D
var right_forearm_mesh: MeshInstance3D
var left_hand_mesh: MeshInstance3D
var right_hand_mesh: MeshInstance3D
var left_grip_target: Marker3D
var right_grip_target: Marker3D
var attachment_sockets: Dictionary = {}
var proxy_visuals: Array[GeometryInstance3D] = []
var proxy_visuals_visible: bool = true
var production_animation: SocomOperatorAnimationDriver

var gait_time: float = 0.0
var gait_strength: float = 0.0
var crouch_amount: float = 0.0
var prone_amount: float = 0.0
var torso_yaw: float = 0.0
var torso_pitch: float = 0.0
var head_yaw: float = 0.0
var weapon_aim_error_deg: float = 0.0
var weapon_obstruction_amount: float = 0.0
var weapon_cover_offset := Vector3.ZERO
var weapon_cover_pose_found: bool = true
var weapon_rest_position := Vector3(0.12, -0.02, -0.23)

@export_group("Upper-body aim")
@export var torso_yaw_limit_deg: float = 52.0
@export var torso_pitch_down_deg: float = 18.0
@export var torso_pitch_up_deg: float = 24.0
@export var torso_follow_response: float = 10.0
@export var head_extra_yaw_deg: float = 18.0
@export var head_follow_response: float = 14.0
@export var weapon_pitch_scale: float = 0.85
@export var weapon_obstruction_distance: float = 1.0
@export var weapon_obstruction_retract: float = 0.42
@export var weapon_obstruction_raise: float = 0.14
@export var weapon_cover_side_step: float = 0.20
@export var weapon_cover_raise: float = 0.20
@export var weapon_obstruction_enter_response: float = 18.0
@export var weapon_obstruction_exit_response: float = 8.0
@export_group("Animation mapping")
@export var animation_profile: SocomOperatorAnimationProfile = DEFAULT_ANIMATION_PROFILE

func _ready() -> void:
    _build_rig()
    production_animation = OperatorAnimationDriver.new()
    production_animation.name = "ProductionAnimation"
    production_animation.animation_profile = animation_profile
    add_child(production_animation)
    set_proxy_visuals_visible(false)

func play_operator_action(clip_name: StringName, blend_seconds: float = 0.12) -> bool:
    return (
        production_animation != null
        and production_animation.play_action(clip_name, blend_seconds)
    )

func get_operator_animation_clips() -> Array[StringName]:
    if production_animation == null:
        return []
    return production_animation.get_clip_names()

func _process(delta: float) -> void:
    var player := get_parent() as CharacterBody3D
    if player == null:
        return

    _animate_locomotion(player, delta)
    var motion_state: StringName = (
        StringName(player.call("get_motion_state_name"))
        if player.has_method("get_motion_state_name")
        else &"STANDING"
    )
    if motion_state != &"DIVING" and motion_state != &"ROLLING":
        _animate_upper_body(player, delta)

func _animate_locomotion(player: CharacterBody3D, delta: float) -> void:
    var motion_state: StringName = (
        StringName(player.call("get_motion_state_name"))
        if player.has_method("get_motion_state_name")
        else &"STANDING"
    )
    var posture: StringName = (
        StringName(player.call("get_posture_name"))
        if player.has_method("get_posture_name")
        else &"STANDING"
    )
    var target_crouch := 1.0 if posture == &"CROUCHED" else 0.0
    var target_prone := 1.0 if posture == &"PRONE" else 0.0
    if motion_state == &"DIVING":
        target_prone = 1.0
    crouch_amount = lerpf(crouch_amount, target_crouch, 1.0 - exp(-14.0 * delta))
    prone_amount = lerpf(prone_amount, target_prone, 1.0 - exp(-12.0 * delta))

    var horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
    var moving: bool = horizontal_speed > 0.15
    var target_strength: float = clampf(horizontal_speed / 6.5, 0.0, 1.0) if moving else 0.0
    gait_strength = lerp(gait_strength, target_strength, 1.0 - exp(-10.0 * delta))

    if moving:
        gait_time += delta * lerp(5.0, 9.0, gait_strength)

    var leg_swing: float = sin(gait_time) * deg_to_rad(27.0) * gait_strength
    var knee_bend_left: float = maxf(0.0, -sin(gait_time)) * deg_to_rad(28.0) * gait_strength
    var knee_bend_right: float = maxf(0.0, sin(gait_time)) * deg_to_rad(28.0) * gait_strength

    left_hip.rotation.x = leg_swing - deg_to_rad(48.0) * crouch_amount
    right_hip.rotation.x = -leg_swing - deg_to_rad(48.0) * crouch_amount
    left_knee.rotation.x = knee_bend_left + deg_to_rad(82.0) * crouch_amount
    right_knee.rotation.x = knee_bend_right + deg_to_rad(82.0) * crouch_amount

    # Small vertical body travel gives the camera real silhouette motion to solve.
    pelvis_bone.position.y = (
        0.93
        - 0.11 * crouch_amount
        + abs(sin(gait_time * 2.0)) * 0.025 * gait_strength
    )
    spine_bone.rotation.z = sin(gait_time) * deg_to_rad(1.4) * gait_strength

    skeleton_root.position = Vector3(0.0, -0.25 * crouch_amount, 0.0)
    skeleton_root.rotation = Vector3(-deg_to_rad(82.0) * prone_amount, 0.0, 0.0)
    if prone_amount > 0.001:
        skeleton_root.position = skeleton_root.position.lerp(
            Vector3(0.0, 0.34, 0.18),
            prone_amount
        )
        left_hip.rotation.x = lerpf(left_hip.rotation.x, deg_to_rad(8.0), prone_amount)
        right_hip.rotation.x = lerpf(right_hip.rotation.x, deg_to_rad(-8.0), prone_amount)
        left_knee.rotation.x = lerpf(left_knee.rotation.x, deg_to_rad(12.0), prone_amount)
        right_knee.rotation.x = lerpf(right_knee.rotation.x, deg_to_rad(16.0), prone_amount)

    var action_phase: float = (
        float(player.call("get_action_phase"))
        if player.has_method("get_action_phase")
        else 0.0
    )
    if motion_state == &"DIVING":
        var dive_tilt := smoothstep(0.0, 0.62, action_phase)
        skeleton_root.rotation.x = -deg_to_rad(82.0) * dive_tilt
        skeleton_root.position.y = lerpf(0.0, 0.34, dive_tilt)
        skeleton_root.position.z = lerpf(0.0, 0.18, dive_tilt)
        left_hip.rotation.x = deg_to_rad(10.0)
        right_hip.rotation.x = -deg_to_rad(8.0)
        left_knee.rotation.x = deg_to_rad(15.0)
        right_knee.rotation.x = deg_to_rad(18.0)
    elif motion_state == &"ROLLING":
        var roll_side_value: Variant = player.get("roll_side")
        var side: float = float(roll_side_value) if roll_side_value != null else 1.0
        skeleton_root.rotation.x = deg_to_rad(-10.0)
        skeleton_root.rotation.z = TAU * action_phase * side
        skeleton_root.position.y = 0.26 + sin(action_phase * PI) * 0.16
        left_hip.rotation.x = deg_to_rad(-38.0)
        right_hip.rotation.x = deg_to_rad(-38.0)
        left_knee.rotation.x = deg_to_rad(92.0)
        right_knee.rotation.x = deg_to_rad(92.0)
    elif motion_state == &"LANDING":
        var landing_compression := sin(action_phase * PI)
        skeleton_root.position.y -= 0.18 * landing_compression
        left_hip.rotation.x -= deg_to_rad(24.0) * landing_compression
        right_hip.rotation.x -= deg_to_rad(24.0) * landing_compression
        left_knee.rotation.x += deg_to_rad(46.0) * landing_compression
        right_knee.rotation.x += deg_to_rad(46.0) * landing_compression
    elif motion_state == &"AIRBORNE":
        var air_tuck := clampf(1.0 - absf(player.velocity.y) / 6.2, 0.22, 1.0)
        skeleton_root.position.y += 0.08 * air_tuck
        left_hip.rotation.x -= deg_to_rad(20.0) * air_tuck
        right_hip.rotation.x -= deg_to_rad(20.0) * air_tuck
        left_knee.rotation.x += deg_to_rad(54.0) * air_tuck
        right_knee.rotation.x += deg_to_rad(54.0) * air_tuck

    _update_camera_markers(motion_state, action_phase)

func _update_camera_markers(motion_state: StringName, action_phase: float) -> void:
    if head_marker == null or torso_marker == null or pelvis_marker == null:
        return
    var standing_head := Vector3(0.0, 2.15, 0.0)
    var standing_torso := Vector3(0.0, 1.52, 0.0)
    var standing_pelvis := Vector3(0.0, 0.93, 0.0)
    var crouched_head := Vector3(0.0, 1.58, 0.0)
    var crouched_torso := Vector3(0.0, 1.12, 0.0)
    var crouched_pelvis := Vector3(0.0, 0.66, 0.0)
    var prone_head := Vector3(0.0, 0.52, -0.18)
    var prone_torso := Vector3(0.0, 0.42, 0.02)
    var prone_pelvis := Vector3(0.0, 0.36, 0.28)

    var stable_head := standing_head.lerp(crouched_head, crouch_amount)
    var stable_torso := standing_torso.lerp(crouched_torso, crouch_amount)
    var stable_pelvis := standing_pelvis.lerp(crouched_pelvis, crouch_amount)
    stable_head = stable_head.lerp(prone_head, prone_amount)
    stable_torso = stable_torso.lerp(prone_torso, prone_amount)
    stable_pelvis = stable_pelvis.lerp(prone_pelvis, prone_amount)

    if motion_state == &"DIVING":
        var dive_blend := smoothstep(0.0, 0.70, action_phase)
        stable_head = standing_head.lerp(prone_head, dive_blend)
        stable_torso = standing_torso.lerp(prone_torso, dive_blend)
        stable_pelvis = standing_pelvis.lerp(prone_pelvis, dive_blend)
    elif motion_state == &"ROLLING":
        var roll_compression := sin(action_phase * PI)
        stable_head = crouched_head.lerp(Vector3(0.0, 0.88, 0.0), roll_compression)
        stable_torso = crouched_torso.lerp(Vector3(0.0, 0.66, 0.0), roll_compression)
        stable_pelvis = crouched_pelvis.lerp(Vector3(0.0, 0.50, 0.0), roll_compression)

    head_marker.position = stable_head
    torso_marker.position = stable_torso
    pelvis_marker.position = stable_pelvis

func _animate_upper_body(player: CharacterBody3D, delta: float) -> void:
    var rig = get_tree().get_first_node_in_group("socom_camera_rig")
    if rig == null:
        return

    # Difference between where the lower body currently faces and where the camera
    # is aiming. This is the torso twist, clamped so the body never becomes rubber.
    var player_yaw: float = player.global_rotation.y
    var aim_yaw: float = float(rig.get("aim_yaw"))
    var aim_pitch: float = float(rig.get("aim_pitch"))
    var relative_yaw: float = (
        float(player.call("get_aim_relative_yaw"))
        if player.has_method("get_aim_relative_yaw")
        else wrapf(aim_yaw - player_yaw, -PI, PI)
    )
    var yaw_limit: float = deg_to_rad(torso_yaw_limit_deg)
    var target_torso_yaw: float = clampf(relative_yaw, -yaw_limit, yaw_limit)

    var target_torso_pitch: float = clampf(
        aim_pitch,
        deg_to_rad(-torso_pitch_down_deg),
        deg_to_rad(torso_pitch_up_deg)
    )

    torso_yaw = lerp_angle(torso_yaw, target_torso_yaw, 1.0 - exp(-torso_follow_response * delta))
    torso_pitch = lerp(torso_pitch, target_torso_pitch, 1.0 - exp(-torso_follow_response * delta))

    chest_bone.rotation.y = torso_yaw
    chest_bone.rotation.x = torso_pitch * 0.42
    # Solve the weapon against the shared camera target, not against a second
    # independently projected crosshair. Near cover the rifle first searches a
    # few restrained shoulder poses. The arms follow those grip targets through
    # IK; if none has a clean muzzle path, the rifle tucks and the shot remains
    # blocked instead of firing through geometry.
    var desired_cover_offset := Vector3.ZERO
    if rig.weapon_aim_point != Vector3.ZERO:
        desired_cover_offset = _find_clear_weapon_offset(player, rig.weapon_aim_point)
    var obstruction_target: float = 0.0
    if not weapon_cover_pose_found:
        obstruction_target = 1.0
        desired_cover_offset = (
            Vector3.BACK * weapon_obstruction_retract
            + Vector3.UP * weapon_obstruction_raise
        )
    var obstruction_response: float = (
        weapon_obstruction_enter_response
        if desired_cover_offset.length() > weapon_cover_offset.length()
        else weapon_obstruction_exit_response
    )
    weapon_cover_offset = weapon_cover_offset.lerp(
        desired_cover_offset,
        1.0 - exp(-obstruction_response * delta)
    )
    weapon_obstruction_amount = lerpf(
        weapon_obstruction_amount,
        obstruction_target,
        1.0 - exp(-obstruction_response * delta)
    )
    weapon_bone.position = weapon_rest_position + weapon_cover_offset

    if rig.weapon_aim_point != Vector3.ZERO:
        weapon_bone.look_at(rig.weapon_aim_point, Vector3.UP)
        var weapon_forward: Vector3 = -muzzle_marker.global_basis.z
        var desired_weapon_direction: Vector3 = (rig.weapon_aim_point - muzzle_marker.global_position).normalized()
        weapon_aim_error_deg = rad_to_deg(acos(clampf(weapon_forward.dot(desired_weapon_direction), -1.0, 1.0)))

    # Head can finish a little more of the turn than the ribcage, like a person
    # visually checking the camera/aim direction before the feet catch up.
    var residual_yaw: float = relative_yaw - torso_yaw
    var head_limit: float = deg_to_rad(head_extra_yaw_deg)
    var target_head_yaw: float = clampf(residual_yaw, -head_limit, head_limit)
    head_yaw = lerp_angle(head_yaw, target_head_yaw, 1.0 - exp(-head_follow_response * delta))
    head_bone.rotation.y = head_yaw
    head_bone.rotation.x = torso_pitch * 0.25
    _solve_weapon_hands()

    if production_animation != null:
        var local_velocity := player.global_basis.inverse() * player.velocity
        var visual_direction := Vector2(local_velocity.x, -local_velocity.z)
        var normalized_speed := clampf(visual_direction.length() / 6.5, 0.0, 1.0)
        if visual_direction.length_squared() > 0.001:
            visual_direction = visual_direction.normalized() * normalized_speed
        var posture_name: StringName = (
            StringName(player.call("get_posture_name"))
            if player.has_method("get_posture_name")
            else &"STANDING"
        )
        var state_name: StringName = (
            StringName(player.call("get_motion_state_name"))
            if player.has_method("get_motion_state_name")
            else &"STANDING"
        )
        production_animation.set_visual_inputs(
            visual_direction,
            posture_name,
            relative_yaw,
            aim_pitch,
            1.0,
            false,
            weapon_obstruction_amount,
            normalized_speed,
            state_name
        )

func _find_clear_weapon_offset(player: CharacterBody3D, target_point: Vector3) -> Vector3:
    var saved_position: Vector3 = weapon_bone.position
    var saved_basis: Basis = weapon_bone.basis
    var candidates: Array[Vector3] = [
        Vector3.ZERO,
        Vector3.UP * weapon_cover_raise,
        Vector3.LEFT * weapon_cover_side_step,
        Vector3.RIGHT * weapon_cover_side_step,
        Vector3.LEFT * weapon_cover_side_step + Vector3.UP * weapon_cover_raise,
        Vector3.RIGHT * weapon_cover_side_step + Vector3.UP * weapon_cover_raise,
    ]
    var selected := Vector3.ZERO
    var found: bool = false
    for candidate in candidates:
        weapon_bone.position = weapon_rest_position + candidate
        weapon_bone.look_at(target_point, Vector3.UP)
        if not _weapon_pose_blocked(player, target_point):
            selected = candidate
            found = true
            break
    weapon_bone.position = saved_position
    weapon_bone.basis = saved_basis
    weapon_cover_pose_found = found
    return selected if found else Vector3.ZERO

func _weapon_pose_blocked(player: CharacterBody3D, target_point: Vector3) -> bool:
    if target_point == Vector3.ZERO:
        return false
    if (
        _pose_segment_blocked(player, weapon_bone.global_position, muzzle_marker.global_position)
        or _pose_segment_blocked(player, left_shoulder.global_position, left_grip_target.global_position)
        or _pose_segment_blocked(player, right_shoulder.global_position, right_grip_target.global_position)
    ):
        return true
    var query := PhysicsRayQueryParameters3D.create(
        muzzle_marker.global_position,
        target_point
    )
    query.collide_with_areas = false
    query.exclude = [player.get_rid()]
    var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    return (
        not result.is_empty()
        and Vector3(result["position"]).distance_to(target_point) > 0.08
    )

func _pose_segment_blocked(
    player: CharacterBody3D,
    segment_start: Vector3,
    segment_end: Vector3
) -> bool:
    var query := PhysicsRayQueryParameters3D.create(segment_start, segment_end)
    query.collide_with_areas = false
    query.exclude = [player.get_rid()]
    return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _build_rig() -> void:
    var uniform := _material(Color(0.20, 0.24, 0.22))
    var gear := _material(Color(0.10, 0.12, 0.11))
    var skin := _material(Color(0.48, 0.38, 0.30))
    var boot := _material(Color(0.07, 0.075, 0.07))
    var weapon := _material(Color(0.055, 0.06, 0.058))

    # Gameplay logic owns this lightweight logical skeleton. The calibration
    # body below is only one visual skin; Sprite3D, MeshInstance3D, equipment,
    # and a future imported rig can mount to the same named sockets.
    skeleton_root = Node3D.new()
    skeleton_root.name = "SkeletonRoot"
    add_child(skeleton_root)

    pelvis_bone = Node3D.new()
    pelvis_bone.name = "PelvisBone"
    pelvis_bone.position = Vector3(0, 0.93, 0)
    skeleton_root.add_child(pelvis_bone)
    _box_on(pelvis_bone, "Pelvis", Vector3(0.54, 0.28, 0.30), Vector3.ZERO, uniform)

    spine_bone = Node3D.new()
    spine_bone.name = "SpineBone"
    spine_bone.position = Vector3(0, 0.27, 0)
    pelvis_bone.add_child(spine_bone)
    _box_on(spine_bone, "Abdomen", Vector3(0.48, 0.42, 0.28), Vector3.ZERO, uniform)

    chest_bone = Node3D.new()
    chest_bone.name = "ChestAimBone"
    chest_bone.position = Vector3(0, 0.32, 0)
    spine_bone.add_child(chest_bone)
    _box_on(chest_bone, "Chest", Vector3(0.68, 0.42, 0.34), Vector3.ZERO, uniform)
    _box_on(chest_bone, "Pack", Vector3(0.46, 0.52, 0.18), Vector3(0, -0.08, 0.25), gear)

    neck_bone = Node3D.new()
    neck_bone.name = "NeckBone"
    neck_bone.position = Vector3(0, 0.30, 0)
    chest_bone.add_child(neck_bone)
    _cylinder_on(neck_bone, "Neck", 0.09, 0.16, Vector3(0, 0.02, 0), skin)

    head_bone = Node3D.new()
    head_bone.name = "HeadAimBone"
    head_bone.position = Vector3(0, 0.19, 0)
    neck_bone.add_child(head_bone)
    head_mesh = _sphere_on(head_bone, "Head", 0.22, Vector3.ZERO, skin)
    helmet_mesh = _box_on(head_bone, "Helmet", Vector3(0.46, 0.16, 0.43), Vector3(0, 0.14, 0), gear)
    head_mesh.set_layer_mask_value(20, true)
    helmet_mesh.set_layer_mask_value(20, true)

    _build_arms(uniform, skin)
    _build_legs(uniform, boot)
    _build_rifle(weapon)
    _build_markers()
    _build_attachment_sockets()

func set_near_camera_crop(active: bool) -> void:
    # Keep the complete operator in the workbench spectator layer while the
    # gameplay camera omits only geometry intersecting its near plane.
    if head_mesh:
        head_mesh.set_layer_mask_value(1, not active)
    if helmet_mesh:
        helmet_mesh.set_layer_mask_value(1, not active)

func _build_arms(uniform: StandardMaterial3D, skin: StandardMaterial3D) -> void:
    left_shoulder = Node3D.new()
    left_shoulder.name = "LeftShoulderBone"
    left_shoulder.position = Vector3(-0.40, 0.08, -0.02)
    left_shoulder.rotation_degrees = Vector3(-48, 8, -12)
    chest_bone.add_child(left_shoulder)
    left_upper_arm_mesh = _capsule_on(left_shoulder, "LeftUpperArm", 0.075, 0.46, Vector3(0, -0.23, 0), uniform)

    left_elbow = Node3D.new()
    left_elbow.name = "LeftElbowBone"
    left_elbow.position = Vector3(0, -0.44, 0)
    left_elbow.rotation_degrees = Vector3(-68, -8, 7)
    left_shoulder.add_child(left_elbow)
    left_forearm_mesh = _capsule_on(left_elbow, "LeftForearm", 0.065, 0.42, Vector3(0, -0.21, 0), uniform)
    left_hand_bone = Node3D.new()
    left_hand_bone.name = "LeftHandBone"
    left_hand_bone.position = Vector3(0, -0.44, 0)
    left_elbow.add_child(left_hand_bone)
    left_hand_mesh = _sphere_on(left_hand_bone, "LeftHand", 0.082, Vector3.ZERO, skin)

    right_shoulder = Node3D.new()
    right_shoulder.name = "RightShoulderBone"
    right_shoulder.position = Vector3(0.40, 0.08, -0.02)
    right_shoulder.rotation_degrees = Vector3(-61, -10, 10)
    chest_bone.add_child(right_shoulder)
    right_upper_arm_mesh = _capsule_on(right_shoulder, "RightUpperArm", 0.075, 0.46, Vector3(0, -0.23, 0), uniform)

    right_elbow = Node3D.new()
    right_elbow.name = "RightElbowBone"
    right_elbow.position = Vector3(0, -0.44, 0)
    right_elbow.rotation_degrees = Vector3(-79, 7, -5)
    right_shoulder.add_child(right_elbow)
    right_forearm_mesh = _capsule_on(right_elbow, "RightForearm", 0.065, 0.42, Vector3(0, -0.21, 0), uniform)
    right_hand_bone = Node3D.new()
    right_hand_bone.name = "RightHandBone"
    right_hand_bone.position = Vector3(0, -0.44, 0)
    right_elbow.add_child(right_hand_bone)
    right_hand_mesh = _sphere_on(right_hand_bone, "RightHand", 0.082, Vector3.ZERO, skin)

func _build_legs(uniform: StandardMaterial3D, boot: StandardMaterial3D) -> void:
    left_hip = Node3D.new()
    left_hip.name = "LeftHipBone"
    left_hip.position = Vector3(-0.18, -0.08, 0)
    pelvis_bone.add_child(left_hip)
    _capsule_on(left_hip, "LeftThigh", 0.105, 0.56, Vector3(0, -0.28, 0), uniform)

    left_knee = Node3D.new()
    left_knee.name = "LeftKneeBone"
    left_knee.position = Vector3(0, -0.56, 0)
    left_hip.add_child(left_knee)
    _capsule_on(left_knee, "LeftShin", 0.09, 0.52, Vector3(0, -0.26, 0), uniform)
    _box_on(left_knee, "LeftBoot", Vector3(0.22, 0.16, 0.38), Vector3(0, -0.56, -0.07), boot)

    right_hip = Node3D.new()
    right_hip.name = "RightHipBone"
    right_hip.position = Vector3(0.18, -0.08, 0)
    pelvis_bone.add_child(right_hip)
    _capsule_on(right_hip, "RightThigh", 0.105, 0.56, Vector3(0, -0.28, 0), uniform)

    right_knee = Node3D.new()
    right_knee.name = "RightKneeBone"
    right_knee.position = Vector3(0, -0.56, 0)
    right_hip.add_child(right_knee)
    _capsule_on(right_knee, "RightShin", 0.09, 0.52, Vector3(0, -0.26, 0), uniform)
    _box_on(right_knee, "RightBoot", Vector3(0.22, 0.16, 0.38), Vector3(0, -0.56, -0.07), boot)

func _build_rifle(material: StandardMaterial3D) -> void:
    weapon_bone = Node3D.new()
    weapon_bone.name = "RifleAimBone"
    weapon_bone.position = weapon_rest_position
    chest_bone.add_child(weapon_bone)

    _box_on(weapon_bone, "RifleReceiver", Vector3(0.13, 0.14, 0.58), Vector3(0, 0, -0.22), material)
    _box_on(weapon_bone, "RifleStock", Vector3(0.16, 0.18, 0.34), Vector3(0.04, -0.01, 0.22), material)
    _box_on(weapon_bone, "RifleBarrel", Vector3(0.055, 0.055, 0.70), Vector3(0, 0.015, -0.83), material)
    _box_on(weapon_bone, "RifleHandguard", Vector3(0.12, 0.12, 0.36), Vector3(0, -0.005, -0.54), material)
    _box_on(weapon_bone, "RifleSight", Vector3(0.06, 0.10, 0.12), Vector3(0, 0.12, -0.25), material)

    muzzle_marker = Marker3D.new()
    muzzle_marker.name = "MuzzleMarker"
    muzzle_marker.position = Vector3(0, 0.015, -1.20)
    weapon_bone.add_child(muzzle_marker)

    left_grip_target = Marker3D.new()
    left_grip_target.name = "LeftHandGrip"
    left_grip_target.position = Vector3(-0.14, -0.045, -0.53)
    weapon_bone.add_child(left_grip_target)

    right_grip_target = Marker3D.new()
    right_grip_target.name = "RightHandGrip"
    right_grip_target.position = Vector3(0.11, -0.055, -0.16)
    weapon_bone.add_child(right_grip_target)

func _solve_weapon_hands() -> void:
    if left_grip_target == null or right_grip_target == null:
        return

    var lateral: Vector3 = global_basis.x.normalized()
    _solve_arm_ik(
        left_shoulder,
        left_elbow,
        left_hand_bone,
        left_upper_arm_mesh,
        left_forearm_mesh,
        left_grip_target.global_position,
        (-lateral + Vector3.DOWN * 0.35).normalized()
    )
    _solve_arm_ik(
        right_shoulder,
        right_elbow,
        right_hand_bone,
        right_upper_arm_mesh,
        right_forearm_mesh,
        right_grip_target.global_position,
        (lateral + Vector3.DOWN * 0.35).normalized()
    )

func _solve_arm_ik(
    shoulder: Node3D,
    elbow: Node3D,
    hand: Node3D,
    upper_mesh: MeshInstance3D,
    forearm_mesh: MeshInstance3D,
    hand_target: Vector3,
    pole_direction: Vector3
) -> void:
    var shoulder_position: Vector3 = shoulder.global_position
    var reach: Vector3 = hand_target - shoulder_position
    var raw_distance: float = reach.length()
    if raw_distance < 0.001:
        return

    var upper_length := 0.52
    var forearm_length := 0.52
    var distance: float = clampf(raw_distance, 0.06, upper_length + forearm_length - 0.001)
    var direction: Vector3 = reach / raw_distance
    var elbow_along: float = (
        upper_length * upper_length
        - forearm_length * forearm_length
        + distance * distance
    ) / (2.0 * distance)
    var elbow_height: float = sqrt(maxf(upper_length * upper_length - elbow_along * elbow_along, 0.0))
    var projected_pole: Vector3 = pole_direction - direction * pole_direction.dot(direction)
    if projected_pole.length_squared() < 0.0001:
        projected_pole = direction.cross(Vector3.UP)
    projected_pole = projected_pole.normalized()

    var elbow_position: Vector3 = shoulder_position + direction * elbow_along + projected_pole * elbow_height
    elbow.global_position = elbow_position
    hand.global_position = hand_target
    hand.global_basis = weapon_bone.global_basis
    _align_limb_mesh(upper_mesh, shoulder_position, elbow_position, 0.46)
    _align_limb_mesh(forearm_mesh, elbow_position, hand_target, 0.42)

func _align_limb_mesh(mesh: MeshInstance3D, start: Vector3, end: Vector3, base_height: float) -> void:
    var segment: Vector3 = end - start
    var length: float = segment.length()
    if length < 0.001:
        return
    var rotation_basis := Basis(Quaternion(Vector3.DOWN, segment / length))
    mesh.global_basis = rotation_basis.scaled(Vector3(1.0, length / base_height, 1.0))
    mesh.global_position = (start + end) * 0.5

func _build_markers() -> void:
    head_marker = Marker3D.new()
    head_marker.name = "HeadMarker"
    head_marker.position = Vector3(0.0, 2.15, 0.0)
    add_child(head_marker)

    torso_marker = Marker3D.new()
    torso_marker.name = "TorsoMarker"
    torso_marker.position = Vector3(0.0, 1.52, 0.0)
    add_child(torso_marker)

    pelvis_marker = Marker3D.new()
    pelvis_marker.name = "PelvisMarker"
    pelvis_marker.position = Vector3(0.0, 0.93, 0.0)
    add_child(pelvis_marker)

    # A stable ground-level framing reference. It intentionally does not follow
    # either animated boot, which keeps gait from making the camera bob.
    feet_marker = Marker3D.new()
    feet_marker.name = "FeetMarker"
    feet_marker.position = Vector3(0.0, 0.04, 0.0)
    add_child(feet_marker)

func _build_attachment_sockets() -> void:
    # Stable public names are the contract between animation/gameplay and art.
    # A replacement visual never needs to know how this calibration proxy was
    # assembled; it only asks for one of these sockets.
    _register_socket(&"root", skeleton_root)
    _register_socket(&"pelvis", pelvis_bone)
    _register_socket(&"spine", spine_bone)
    _register_socket(&"chest", chest_bone)
    _register_socket(&"neck", neck_bone)
    _register_socket(&"head", head_bone)
    _register_socket(&"left_shoulder", left_shoulder)
    _register_socket(&"left_elbow", left_elbow)
    _register_socket(&"left_hand", left_hand_bone)
    _register_socket(&"right_shoulder", right_shoulder)
    _register_socket(&"right_elbow", right_elbow)
    _register_socket(&"right_hand", right_hand_bone)
    _register_socket(&"left_hip", left_hip)
    _register_socket(&"left_knee", left_knee)
    _register_socket(&"right_hip", right_hip)
    _register_socket(&"right_knee", right_knee)
    _register_socket(&"weapon", weapon_bone)
    _register_socket(&"muzzle", muzzle_marker)

    _register_socket(&"face", _socket_on(head_bone, "FaceSocket", Vector3(0, 0.01, -0.23)))
    _register_socket(&"helmet", _socket_on(head_bone, "HelmetSocket", Vector3(0, 0.14, 0)))
    _register_socket(&"back", _socket_on(chest_bone, "BackSocket", Vector3(0, -0.04, 0.24)))
    _register_socket(&"left_foot", _socket_on(left_knee, "LeftFootSocket", Vector3(0, -0.56, -0.07)))
    _register_socket(&"right_foot", _socket_on(right_knee, "RightFootSocket", Vector3(0, -0.56, -0.07)))

func _register_socket(socket_name: StringName, socket: Node3D) -> void:
    attachment_sockets[socket_name] = socket

func _socket_on(parent: Node3D, socket_name: String, position: Vector3) -> Marker3D:
    var socket := Marker3D.new()
    socket.name = socket_name
    socket.position = position
    parent.add_child(socket)
    return socket

func get_attachment_socket(socket_name: StringName) -> Node3D:
    return attachment_sockets.get(socket_name) as Node3D

func get_attachment_socket_names() -> Array[StringName]:
    var names: Array[StringName] = []
    for socket_name in attachment_sockets:
        names.append(socket_name as StringName)
    names.sort()
    return names

func mount_visual(
    socket_name: StringName,
    visual: Node3D,
    keep_global_transform: bool = false
) -> bool:
    var socket := get_attachment_socket(socket_name)
    if socket == null or visual == null:
        return false
    if visual.get_parent() == null:
        socket.add_child(visual)
    else:
        visual.reparent(socket, keep_global_transform)
    if not keep_global_transform:
        visual.transform = Transform3D.IDENTITY
    visual.set_meta("socom_attachment", true)
    visual.set_meta("socom_socket", socket_name)
    return true

func clear_mounted_visuals(socket_name: StringName) -> void:
    var socket := get_attachment_socket(socket_name)
    if socket == null:
        return
    for child in socket.get_children():
        if child.has_meta("socom_attachment"):
            child.queue_free()

func set_proxy_visuals_visible(active: bool) -> void:
    proxy_visuals_visible = active
    for visual in proxy_visuals:
        if is_instance_valid(visual):
            visual.visible = active

func _box_on(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    proxy_visuals.append(part)
    return part

func _sphere_on(parent: Node3D, part_name: String, radius: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    proxy_visuals.append(part)
    return part

func _cylinder_on(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    proxy_visuals.append(part)
    return part

func _capsule_on(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    proxy_visuals.append(part)
    return part

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.8
    return material

func get_aim_debug_data() -> Dictionary:
    return {
        "torso_yaw_deg": rad_to_deg(torso_yaw),
        "torso_pitch_deg": rad_to_deg(torso_pitch),
        "head_yaw_deg": rad_to_deg(head_yaw),
        "muzzle": muzzle_marker.global_position if muzzle_marker else Vector3.ZERO,
        "weapon_aim_error_deg": weapon_aim_error_deg,
        "weapon_obstruction_amount": weapon_obstruction_amount,
        "left_hand_error": left_hand_mesh.global_position.distance_to(left_grip_target.global_position) if left_hand_mesh and left_grip_target else -1.0,
        "right_hand_error": right_hand_mesh.global_position.distance_to(right_grip_target.global_position) if right_hand_mesh and right_grip_target else -1.0
    }
